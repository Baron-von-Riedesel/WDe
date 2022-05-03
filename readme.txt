
  1. About

   WDe is designed to be a modular disk editor capable of allowing users
  to manipulate data stored in various ways on different kinds of storage
  mediums.

   WDe is currently capable of editing logical, physical and CD-Rom drives
  on MS-DOS V4.0+ or compatible.  It understands all FAT file systems, 
  including exFAT. It should be able to edit drives up to 2 TB in size.

   Please be aware that a disk editor, if used inappropriately, might easily
  cause severe data losses. WDe is no exception in this regard, on the
  contrary, it generally assumes that the user knows exactly what he/she
  is doing and will begin any job that is is told to do instantly, without
  confirmation. So if you're not accustomed to WDe's user interface yet, 
  don't experiment with storage devices that hold important data - unless
  you love to live dangerously!
   

  2. User Interface

   WDe has a text mode interface. It needs at least 43 rows and 80 columns.
  If the current text mode has less than 43 rows, WDE will switch to the
  standard text mode, but loads the 8x8 font instead of the usual 8x16 one
  and restricts the scan lines to 350, thus achieving the needed 43 rows.

   There are 2 small tools, SETM43/SETM432, supplied. These may allow WDE
  to use a better looking font (8x14) with still 43 lines, but there is no
  guarantee that any of those tools runs with your graphics card - they use
  a heavily modified VESA mode 0x102, something that may work or not.


  3. Environment

   WDe is supposed to run in DOS. There's a support dll supplied (WDEVDD.DLL),
  that may allow to run WDe in Windows XP or Vista as administrator, but this
  is unsupported and won't work with newer versions of Windows. Also note that
  WDe needs at least a 80386 cpu to run.


  4. Creating the Binaries

  In case one wants to create the binaries from the source:

   WDe and the optional tools ( SETM43 and WDEVDD.DLL ) are written in
  Masm-style assembly language. They are supposed to be created by JWasm;
  Masm may also be used, but this additionally requires an OMF linker for
  WDe ( and SETM43 ) and a COFF linker for WDEVDD.DLL. Both a simple batch
  file ( build.bat ) and a Makefile are supplied that will do the job.
  The source can be found at https://github.com/Baron-von-Riedesel/WDe.

   The build tools will also create wdex.com, a version of WDe that runs
  in protected-mode as 16-bit DPMI client. There is currently no real benefit
  using this binary. However, since protected-mode offers access to huge
  amounts of memory, it may allow to implement things that the real-mode
  WDe can't efficiently accomplish, for example, read in the whole FAT
  ( or directory structure ) of a drive and thus speed up certain functions
  considerably.


  5. License

  WDe Copyright(C)2005 Ben Cadieux (ben.cadieux@gmail.com)
  
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

