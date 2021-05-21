// modules for the clockwork workflow

process alignToRef {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }

    publishDir "${params.output_dir}/$sample_name/output_bam", mode: 'copy', overwrite: 'true', pattern: '*{.bam,.bam.bai,_alignmentStats.json}'
    publishDir "${params.output_dir}/$sample_name", mode: 'copy', overwrite: 'true', pattern: '*{.err,_report.json}'

    cpus 12

    when:
    doWeAlign = ~ /NOW\_ALIGN\_TO\_REF\_${sample_name}/

    input:
    tuple val(sample_name), path(fq1), path(fq2) 
    tuple path(json), val(doWeAlign)

    output:
    tuple val(sample_name), path("${sample_name}_report.json"), path("${sample_name}.bam"), stdout, emit: alignToRef_mpileup
    path("${sample_name}.bam.bai", emit: alignToRef_bai)
    path("${sample_name}_alignmentStats.json", emit: alignToRef_json)
    path("${sample_name}.err", emit: alignToRef_err)

    script:
    bam = "${sample_name}.bam"
    bai = "${sample_name}.bam.bai"
    stats = "${sample_name}.stats"
    stats_json = "${sample_name}_alignmentStats.json"
    out_json = "${sample_name}_report.json"
    error_log = "${sample_name}.err"

    """
    ref_fa=\$(jq -r '.top_hit.file_paths.ref_fa' ${json})

    minimap2 -ax sr \$ref_fa -t ${task.cpus} $fq1 $fq2 | samtools fixmate -m - - | samtools sort -T tmp - | samtools markdup --reference \$ref_fa - minimap.bam

    java -jar /usr/local/bin/picard.jar AddOrReplaceReadGroups INPUT=minimap.bam OUTPUT=${bam} RGID=${sample_name} RGLB=lib RGPL=Illumina RGPU=unit RGSM=sample

    samtools index ${bam} ${bai}
    samtools stats ${bam} > ${stats}

    python3 ${baseDir}/bin/parse_samtools_stats.py ${bam} ${stats} > ${stats_json}
    perl ${baseDir}/bin/create_final_json.pl ${stats_json} ${json}

    continue=\$(jq -r '.summary_questions.continue_to_clockwork' ${out_json})
    if [ \$continue == 'yes' ]; then printf "NOW_VARCALL_${sample_name}" && printf "" >> ${error_log}; elif [ \$continue == 'no' ]; then echo "error: insufficient number and/or quality of read alignments to the reference genome" >> ${error_log}; fi
    """
}

process callVarsMpileup {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }

    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf'

    cpus 12

    when:
    do_we_varcall =~ /NOW\_VARCALL\_${sample_name}/

    input:
    tuple val(sample_name), path(json), path(bam), val(doWeVarCall)

    output:
    tuple val(sample_name), path(json), path(bam), path("${sample_name}.samtools.vcf"), emit: mpileup_vcf

    script:
    samtools_vcf = "${sample_name}.samtools.vcf"

    """
    ref_fa=\$(jq -r '.top_hit.file_paths.ref_fa' ${json})
    samtools mpileup -ugf \${ref_fa} ${bam} | bcftools call --threads ${task.cpus} -vm -O v -o ${samtools_vcf}
    """
}