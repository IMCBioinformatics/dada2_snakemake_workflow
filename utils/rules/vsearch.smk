rule vsearchGTDB:
    input:
        fas=rules.multipleAlign.output.seqfasta
    output:
        output1= config["output_dir"]+"/vsearch/GTDB/Vsearch_GTDB_selected.tsv",
        output2= config["output_dir"]+"/vsearch/GTDB/Vsearch_GTDB_raw.tsv"
    threads:
        config['threads']
    conda:
        "vsearch"
    log:
        config["output_dir"]+"/vsearch/logs/GTDB_logfile.txt"
    params:
        db=config["vsearch_DBs"]["GTDB"],
        id=config["Identity"],
        maxaccepts=config["Maxaccepts"]
    shell: 
        "time vsearch --usearch_global {input.fas} --db {params.db} --userout {output.output1} --userfields query+target+id --uc {output.output2} --id {params.id} --iddef 0 --log {log} --threads {threads} --uc_allhits --maxaccepts {params.maxaccepts} --top_hits_only --strand both --gapopen '*' "



rule vsearchParse:
    input:
        GTDB_file=rules.vsearchGTDB.output.output1,
        annotation=rules.combining_annotations.output.table
    output:
        SemiParsed_uncollapsed=config["output_dir"]+"/vsearch/Final_uncollapsed_output.tsv",
        parsed_collapsed_GTDB=config["output_dir"]+"/vsearch/Final_colapsed_output.tsv",
        Vsearch_final=config["output_dir"]+"/taxonomy/Vsearch_output.tsv",
        merged_final=config["output_dir"]+"/taxonomy/vsearch_dada2_merged.tsv"
    threads:
        config['threads']
    conda:
        "dada2"   
    script:
        "../scripts/vsearch/vsearch_parsing.R"

