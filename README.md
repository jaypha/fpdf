FPDF
====

This project is a port of the FPDF project from PHP. I have tried to stay as fatithful
as possible to the PHP version. The following differences:

* Output() only gives back a string. No direct output to a file or stdout.
* Only builtin fonts are supported. (I can't figure out how they work in PDF).

This should not be considered a full solution to the need for PDF support in D, but a
minimalist one.

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
