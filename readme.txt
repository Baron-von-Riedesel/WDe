WDe Copyright(C)2005 Ben Cadieux (ben.cadieux@gmail.com)

WDe.com         V0.30b MD5: 0908554d480fc646c594fe046fd3e985
WDeTest.com     V0.30b MD5: 9d427d3aa2f6ab394ad873271d9870c5

About/License:
  WDe is designed to be a modular disk editor capable of allowing users
  to manipulate data stored in various ways on different kinds of storage
  mediums.

  WDe is currently capable of editing logical, physical and CD-Rom drives
  on MS-DOS V4.0+ or compatible.  It should (theoretically) be able to edit
  drives up to 2 TB in size.

  I strongly recommend using a cache utility (such as SMARTDrive) to speed
  up functions that would otherwise be quite slow.

  This program is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License (Version 2) as published
  by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
  for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

Notes about V0.22b:
  Included in this release is WDeTest.com; a semi-completed new menu
  system being considered for future releases of WDe.  This version should
  only be used as a preview for feedback to the author, since a great
  deal of code needed to be moved or changed to allow for the new menu.
  WDeTest.com may also lack some fixes found in WDe.com.

  The project's future is uncertain, WDe may be ported to Linux or moved
  towards being OS-independant.  There are plans to add support for more
  partition types such as NTFS, UFS and Ext2/3.  Comments, ideas and
  suggestions would be appreciated; a simple e-mail might change WDe's path.

Updates in V0.30b:
  - fixed a small bug in the hex printing code
  - separated int 13h buffers for getting drive info and reading/writing,
  - reversed display of attribute bits in directory view to match binary
  - fixed root cluster number display bug
  - enhanced finding MBR; less chance of a false positive
  - sector saving/restoring can no longer read/write outside drive parameters
  - fixed bug in fat functions allowing them to read/write past fat tables
  - added workaround to Win9x bug for theoretical writes to CD-Roms
  - fixed bootsector display bug that occurred under certain conditions
  - read functions fixed and reversed back to oldest to newest
  - fixed bug switching to drives that were unable to be edited
  - optimized code that converts values to hex strings
  - modified menu system to be more versatile
  - fixed bug getting fat entry data for last few allowable clusters
    on maximally sized Fat12 and Fat16 partitions
  - enhanced/corrected directory detection; less false negatives/positives
  - updated file/path character checking; this further improves directory
    finding and accepts more characters as valid input when undeleting
  - unformat function has been re-designed, re-written and implemented
  - bytes per sector returned by int 13h/48h now used for hard disks
  - hitting enter in the fat area now works regardless of the view set
  - fixed bug causing restore chain to default to second fat in directories
  - fixed rare bug causing Fat16 partitions to be shown as Fat32
  - file sharing violation crashes under windows fixed by having int 24h
    return "fail" instruction to the calling code
  - running out of disk space while writing a file now aborts with an error
  - last sector bound now kept for non-physical drives restricted as physical
  - restricting above as physical now always correctly sets last sector
  - defaults to Fat1 if saving/restoring Fat2 when none exists
  - fixed major partition saving bug (saving was starting at MBR)
  - fixed partition saving/restoring bug causing it to miss last sector
  - fixed CHS display code for high sector numbers
  - CHS no longer displayed when switching from physical to non-physical
  - workarounds added for CHS reading with poorly written BIOSes
  - searching for String/Hex on CDs no longer randomly stops
  - excessive amounts of code clean-up & optimization for speed and size
  - much better system implemented to generate random values
  - fixed some fat type detection problems
  - MBR view now shows Linux, FreeBSD and NTFS as partition types

Planned Updates:
  - directory location function
  - defrag function (maybe)
  - further modularization of source code
  - better CHS hard disk identification (int13h/ah=25h, ah=48h)
  - bootsector view changes to make easy Fat1x/Fat32 distinction
  - 2gb file limit check revising for append
  - 4gb file limit check for fat32
  - rather than filesize limits; file splitting options
  - case insensitive search
  - fat32 root save/restore implemented for all linked clusters
  - better fat finding (entry repetition checking)
  - file chain saving guess cluster order for deleted files
  - restore previous video mode on quit
  - some CD "goto" functions
  - revision of "goto" functions for physical reading of floppy drives
  - drive scan function to report/fix errors
  - editing support (with tab) in view area
  - lfn support for undeleting files
  - support for reading sector numbers that are bigger than a dword
  - searches should move cursor to start of found string
  - searching should have a "find again" feature
  - bug finding fat12 partitions on hard disks (descriptor byte)
  - unreadable sectors should be shown as blanked/dashed
  - save/restore entire hard drive needed
  - ability to mount drives as drive letters (maybe)
  - file manager mode (maybe)
