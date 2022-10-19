
 About

 Compress is a small tool intended to be used together with WDe. It
 "compresses" a directory stored in a file by removing all "deleted"
 entries ( first byte == E5h ). Such an operation may be useful
 specifically for the root directory of a FAT32 disk that has been
 "flooded" with (temporary) files.


 Usage

 - save directory to compress in WDe as file/fat chain.
 - use compress to compress the directory.
 - restore directory in WDe as file/fat chain.


 Restrictions

 To be able to "compress" directories of "any" size, compress has been
 written as 32-bit application and hence needs a DPMI host to run.
 Actually, size of the buffer to read the directory into is 256 kB -
 that should cover most cases. If it does not, constant BUFFSIZE has to
 be adjusted and the program must be recreated using Make.bat.
