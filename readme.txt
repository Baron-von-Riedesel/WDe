
  1. About

  WDe is designed to be a modular disk editor capable of allowing users
  to manipulate data stored in various ways on different kinds of storage
  mediums.

  WDe is currently capable of editing logical, physical and CD-Rom drives
  on MS-DOS V4.0+ or compatible.  It should (theoretically) be able to edit
  drives up to 2 TB in size.

  I strongly recommend using a cache utility (such as SMARTDrive) to speed
  up functions that would otherwise be quite slow.


  2. User Interface

  WDe has a text mode interface. It needs at least 43 rows and 80 columns.
  If the current text mode has less than 43 rows, WDE will switch to the
  standard text mode, but loads the 8x8 font instead of the usual 8x16 one
  and restricts the scan lines to 350, thus achieving the needed 43 rows.

  There's a small tool, SETM43, supplied. This may allow WDE to use a better
  looking font (8x14) with still 43 lines, but SETM43 won't run with all
  graphics cards - it uses a heavily modified VESA mode 0x102, something
  that may work or not.


  3. Environment

  WDe is supposed to run in DOS. There's a support dll supplied (WDEVDD.DLL),
  that may allow to run WDe in Windows XP as administrator, but this is
  unsupported and won't work with newer versions of Windows.


  4. License

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

