#!/usr/bin/env bash
set -euo pipefail

############################
# Configuration
############################
DENSITY="200x200"
JPEG_QUALITY=50
OCR_LANG="ces" # deu, eng, ...
PAPER_SIZE="a4paper"

INPUT_GLOB="*.jpg"

DIR_COMPRESSED="01_compressed"
DIR_PDF_SCAN="02_pdf_scan"

PDF_MERGED="03_merged.pdf"
PDF_A4="04_a4.pdf"
PDF_OCR="05_ocr.pdf"

############################
# Prepare directories
############################
mkdir -p "$DIR_COMPRESSED" "$DIR_PDF_SCAN"

############################
# Step 1: JPEG compression
############################
for file in $INPUT_GLOB; do
  base="$(basename "$file")"
  magick \
    -density "$DENSITY" \
    -quality "$JPEG_QUALITY" \
    -compress jpeg \
    "$file" \
    "$DIR_COMPRESSED/$base"
done

############################
# Step 2: JPG -> PDF (per page)
############################
for file in "$DIR_COMPRESSED"/*.jpg; do
  base="$(basename "$file" .jpg)"
  magick "$file" "$DIR_PDF_SCAN/$base.pdf"
done

############################
# Step 3: Merge PDFs
############################
pdfunite "$DIR_PDF_SCAN"/*.pdf "$PDF_MERGED"

############################
# Step 4: Normalize to A4
############################
pdfjam "$PDF_MERGED" --"$PAPER_SIZE" --outfile "$PDF_A4" >/dev/null 2>&1

############################
# Step 5: OCR
############################
ocrmypdf -l "$OCR_LANG" --output-type=pdf "$PDF_A4" "$PDF_OCR"
