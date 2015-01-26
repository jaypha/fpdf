

module sample;

import jaypha.fpdf;

import std.stdio;

void main()
{
  auto pdf = new Fpdf();
  pdf.AddPage();
  pdf.SetFont("Courier","B",16);
  auto link = pdf.AddLink();
  pdf.Cell(40,10,"Hello World!", "0", 0, "", false, "http://google.com");
  pdf.SetLink(link);
  pdf.SetXY(45, 25);
  pdf.Write(15, "Hello\nWorld!", "http://google.com");
  pdf.AddPage();
  pdf.SetFont("Courier","B",16);
  pdf.Cell(40,10,"Hello World! (p2)", "0", 0, "", false, link);
  pdf.SetXY(0, 25);
  pdf.Write(15, "Hello\nWorld! (p2)", link);

  stdout.rawWrite(pdf.Output());
}
