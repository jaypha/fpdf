

module sample;

import jaypha.fpdf;

import std.stdio;

void main()
{
  auto pdf = new Fpdf();
  pdf.AddPage();
  pdf.SetFont("Courier","B",16);
  pdf.Cell(40,10,"Hello World!");

  write(pdf.Output());
}
