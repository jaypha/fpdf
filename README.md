FPDF
====

This project is a port of the FPDF project from PHP, written by Olivier Plathey. I have
tried to stay as fatithful as possible to the PHP version. The following differences exist:

* Output() only gives back a ubyte array. No direct output to a file or stdout.
* Only builtin fonts are supported. (I can't figure out how they work in PDF).
* Only ISO-8859-1. No Unicode support.
* No GIF support.

This should not be considered a full solution to the need for PDF support in D, but a
minimalist one.

Note. If you don't need to be able to import PDFs, you should check out harud.

Documentation
-------------

Documentation for the original PHP version can be found at http://fpdf.org

There are currently no plans to create a D specific version.

Modules
-------

All my modules are kept under the 'jaypha' umbrella package. The fpdf
library consists of the following modules.

* jaypha.fpdf
* jaypha.fpdf_fonts

License
-------

Distributed under the Boost License.

Todo
----

Port FPDI, which allows the importation of existing PDF documents.

Current Problems
----------------

Linker is unable to find imageformats code. Placing a copy of imageformats.d into your
project fixes this.