# Packages
suppressMessages(library(dplyr))
suppressMessages(library(tibble))


# Read in the output table generated by vsearch and assign column names
output_table_GTDB <- read.table(file= snakemake@input[["GTDB_file"]], sep = '\t', header = F)

# Create a vector of column names for the output table
names <- c("asv_seq", "taxonomy", "identity")

colnames(output_table_GTDB) <- names

# Joining the GTDB output and the first 3 columns of the annotation file 
annotation_table <- read.table(file= snakemake@input[["annotation"]], sep = ',', header = T)
annotation_table<-annotation_table[,1:3]

df<-data.frame(annotation_table) %>% left_join(output_table_GTDB,by="asv_seq",multiple = "all")



# Read in the combined output table of GTDB vsearch
output_table<-df

# Split the 'Taxa' column of the previous data frame into separate columns based on the ';' separator, up to a maximum of 7 columns
taxa_level <- as.data.frame(stringr::str_split_fixed(output_table$taxonomy, ";", n = 7))

# Rename the columns of the resulting data frame to correspond to the taxonomic levels
colnames(taxa_level) <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")

# Add the 'taxa_level' data frame as columns to the output_table data frame
output_table <- output_table %>% mutate(taxa_level) %>% 
    # Add a new 'Species_level' column that checks whether the 'Species' column has any characters or not
    mutate(Species_level = case_when(nchar(taxa_level$Species) > 0 ~ TRUE, nchar(taxa_level$Species) == 0 ~ FALSE), .after = asv_len) %>%
    # Sort the data frame by the 'Species_level' column in descending order
    arrange(desc(Species_level))


# Replace NA values in Identity column with 0
output_table$identity[is.na(output_table$identity)] <- 0

# Replace empty values with NA
output_table[output_table == ""] <- NA 


# Filter the output_table data frame to include only rows where 'Species_level' is TRUE
species_filt <- output_table %>% filter(Species_level == TRUE) %>%
    # Split the 'Species' column into two separate columns based on the '_' separator
    mutate(as.data.frame(stringr::str_split_fixed(Species, "_", n = 2))) %>%
    # Add a new 'Species_unique' column by extracting the unique species name from the second column
    mutate(Species_unique = gsub("\\(.*", "", V2)) %>%
    # Add a new 'Accession_number' column by extracting the accession number from the second column
    mutate(Accession_number = gsub(".*\\((.*)\\).*", "\\1", V2)) %>%
    # Remove the two columns created earlier
    select(-c("V1", "V2")) %>%
    # Remove the first character (a single letter followed by an underscore) from the 'Species_unique' column
    mutate(Species_unique = gsub(pattern = "\\b[A-Za-z]_", replacement = "", x = Species_unique)) %>%
    # Group the data frame by 'ASV_ID', 'Identity', and 'Genus'
    group_by(asv_id, identity, Genus) %>%
    # Summarize the data by concatenating the 'Species', 'Species_unique', and 'Accession_number' columns
    summarize(Species = paste(Species, collapse = "/"),
              Species_unique = paste(unique(Species_unique), collapse = "/"),
              Accession_number = paste(Accession_number, collapse = "/"),
              Num_hits = sum(Species_level)) %>%
    # Rename the 'Species' column to 'Species_raw'
    rename(Species_raw = Species) %>%
    # Move the 'Num_hits' column to appear after 'identity'
    relocate(Num_hits, .after = identity)


# Remove the 'taxonomy' and 'Species' columns from the output_table data frame
output_table2 <- output_table %>% select(-c("taxonomy", "Species"))

# Remove duplicated rows
output_table2 <- output_table2[!duplicated(output_table2), ] %>%
    left_join(species_filt, by = c("asv_id", "identity", "Genus")) %>%
    # Move the 'Num_hits' column to appear after 'Identity'
    relocate(Num_hits, .after = identity) 
   

# Find ASVs with multiple hits and store them in a new data frame called 'repeated_asvs'
repeated_asvs <- output_table2 %>%
    group_by(asv_id) %>%
    filter(n() > 1) %>%   # Keep only rows where the number of occurrences of 'asv_id' is greater than 1
    ungroup()

# Find ASVs with a single hit and store them in a new data frame called 'unique_asvs'
unique_asvs <- output_table2 %>%
    group_by(asv_id) %>%
    filter(n() == 1) %>%   # Keep only rows where the number of occurrences of 'asv_id' is equal to 1
    ungroup()


# Replace NA values in Num_hits column with 1 when it has a hit at another level
unique_asvs$Num_hits[!is.na(unique_asvs$Database) & is.na(unique_asvs$Num_hits)] <- 1


# Group the 'repeated_asvs' data frame by 'asv_id', summarize the number of hits and mean 'Species_level'
test <- repeated_asvs %>%
    group_by(asv_id) %>%
    summarize(n_hits = n(), Mean = mean(Species_level))   #n() gives the current group size
# Create a logical vector 'x' to indicate ASVs with mean 'Species_level' values between 0 and 1
x <- test$Mean > 0 & test$Mean < 1
# If there are ASVs with mean 'Species_level' values between 0 and 1, create a new data frame called 'repeated_asvs_onetrue' that includes only those with a single hit


if (sum(x) > 0) {
    repeated_asvs_onetrue <- repeated_asvs %>%
        filter(Species_level == TRUE) %>%
        group_by(asv_id) %>%
        filter(n() == 1) %>%   #n() gives the current group size
        ungroup()
    repeated_asvs <- repeated_asvs %>% anti_join(repeated_asvs_onetrue, by = "asv_id")
} 

# Remove the rows in 'repeated_asvs' that are also present in 'repeated_asvs_onetrue', and set the 'Species_level' column to FALSE
repeated_asvs$Species_level <- FALSE


# Group by asv_id and check for equal values in each column within a group
repeated_asvs_colapsed <- repeated_asvs %>%
  group_by(asv_id) %>% # Step 1: Group data by asv_id
  #mutate(Num_hits=n())%>%
  summarize_all(       # Step 2 and 3: Check for equal values and replace non-equal values with NA
    ~ ifelse(
      length(unique(.)) == 1, # Check if all values in the column are equal within the group
      first(.),               # If true, retain the value
      NA                      # If false, replace with NA
    )
  )


repeated_asvs_colapsed$Num_hits <- 1

# Combine the 'unique_asvs', 'repeated_asvs_onetrue', and 'repeated_asvs_colapsed' data frames into a single data frame called 'final_result_unique_id'
# if the repeated_asvs_onetrue dataframe is all NA we don't need to join it

if (sum(x) > 0) {
    final_result_unique_id <- rbind(unique_asvs, repeated_asvs_onetrue, 
repeated_asvs_colapsed)
} else {
    final_result_unique_id <- rbind(unique_asvs, repeated_asvs_colapsed)
}

# Replace any NA values in the 'Num_hits' column with 0 using the 'ifelse()' function
final_result_unique_id$Num_hits <- ifelse(is.na(final_result_unique_id$Num_hits), 0, final_result_unique_id$Num_hits)



write.table(output_table,snakemake@output[["SemiParsed_uncollapsed"]],row.names=F,sep="\t")
write.table(final_result_unique_id,snakemake@output[["parsed_collapsed_GTDB"]],row.names=F,sep="\t")


############ merging vsearch and dada2 results #############

# load dada2 final combined output table from output/taxomomy


dd2 <- read.table(file= snakemake@input[["annotation"]], sep = ',', header = T)

# load vsearch final colapsed table from output/vsearch/ and select only desired columns
vsearch<-final_result_unique_id %>% select(c(1:3,5,7:12,14,15)) %>% rename(Species=Species_unique)


# adjust vsearch column names and add a suffix
colnames(vsearch)<-tolower(colnames(vsearch))
colnames(vsearch)[4:12] <- paste0(colnames(vsearch)[4:13], "_vsearch")


# join dada2 and vsearch tables
df<- vsearch %>% left_join(.,dd2,by=c("asv_id","asv_seq","asv_len"))


# create a dataframe to colapse the taxonomy from vsearch + dada2_gtdb + dada2_URE
colapsed <- df[1:3] 
colapsed[c("kingdom_final","phylum_final","class_final","order_final","family_final","genus_final","species_final")]<-df[5:11]

colapsed$database_final<-"GTDB"
colapsed$package<-"Vsearch"

# only dada2 gtdb assignments
gtdb_dd2 <- df[c("kingdom_gtdb","phylum_gtdb","class_gtdb","order_gtdb","family_gtdb","genus_gtdb","species_gtdb")]


# This loop checks if there is a Vsearch assignment to each ASV, if not it checks dada2_gtdb for assignment to any level, if not it tries dada2_URE when URE=TRUE

for(i in 1:nrow(df)){
  if(df$identity_vsearch[i]==0 & all(is.na(gtdb_dd2[i,]))==F){
    colapsed[i,4:10]<- gtdb_dd2[i,]
    colapsed[i,"database_final"]<-"GTDB"
    colapsed[i,"package"]<-"DADA2"
  } else if (df$identity_vsearch[i]==0){
    colapsed[i,"database_final"]<-""
    colapsed[i,"package"]<-""
  }
}


final <- colapsed %>% left_join(.,df,by=c("asv_id","asv_seq","asv_len"))

write.table(final, file = snakemake@output[["merged_final"]], row.names = F, sep = "\t")


##This file can be used for the downstream analysis
selected_final_table <- final %>% 
  select(asv_seq, kingdom_vsearch, phylum_vsearch, class_vsearch, order_vsearch, family_vsearch, genus_vsearch,species_vsearch)

write.table(selected_final_table, snakemake@output[["Vsearch_final"]], sep = "\t",col.names =NA)





