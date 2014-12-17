sis-csv-diff
============

Efficiently compares two CSVs from an SIS system for use in an LMS.

Made for use in Canvas, but may be compatible with other LMSes and related systems.

gui.rb - Shoes frontend GUI
Download Shoes at http://shoesrb.com

csv-diff.rb - Can be used as a console script or imported as a module.

This script has two restrictions*:

1. Both CSVs must have matching headers.
2. Both CSVs must have a "status" column.

\* The code is simple enough that modifying it to suite your needs should be easy.
