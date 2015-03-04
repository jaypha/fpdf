// Written in the D programming language.
/*
 * Sample program for fpdf package.
 *
 * Copyright (C) 2015 Jaypha.
 * Distributed under the Boost License V1.0.
 *
 * Written by Jason den Dulk.
 */

module sample;

import jaypha.fpdf;

import std.stdio;

void main()
{
  auto pdf = new Fpdf();
  pdf.SetCompression(false);
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
  pdf.SetXY(10, 25);
  pdf.Write(15, "Hello\nWorld! (p2)", link);

  auto table = FpdfTable
  (
    pdf,
    [100.5, 40],
    ["L","R"]
  );

  pdf.SetXY(10, 50);
  table.Row(["abcd","efgh"],20);
  table.Row(["1234","5678"],20);

  stdout.rawWrite(pdf.Output());
}
