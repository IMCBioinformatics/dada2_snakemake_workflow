rule qc_report:
    input:
        rules.combineReadCounts.output,
        rules.plotASVLength.output,
        rules.plotQualityProfileAfterdada2.output,
        rules.plotQualityProfileRaw.output,
        rules.plotQualityProfileAfterQC.output
    conda:
        "rmd"
    params:
        Nread=config["output_dir"]+"/dada2/Nreads.tsv",
        quality=config["path"]+"/"+config["output_dir"]+"/figures/quality/",
        length_distribution=config["path"]+"/"+config["output_dir"]+"/figures/length_distribution/",
        taxonomy=config["path"]+"/"+config["output_dir"]+"/taxonomy/GTDB_RDP.tsv",
        seqtab=config["path"]+"/"+config["output_dir"]+"/dada2/seqtab_nochimeras.csv",
        source=config["path"]+"/utils/scripts/dada2/pos_ctrl_references.R",
        pos=config["Positive_samples"],
        ref=config["path"]+"/utils/databases/",
        krona=config["output_dir"]+"/QC_html_report/"+"krona_Species_result"
    output:
        config["output_dir"]+"/QC_html_report/"+"qc_report.html"
    script:
        "../scripts/dada2/qc_report.Rmd"
