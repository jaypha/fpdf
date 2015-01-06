// Written in the D language.
/*
 * Distributed under the Boost License V1.0.
 *
 * Original Author Olivier Plathey
 * D translation by Jason den Dulk.
 */

module jaypha.fpdf;

import jaypha.fpdf_fonts;

import imageformats;

import std.array;
import std.file;
import std.string;
import std.json;
import std.conv;
import std.zlib;
import std.traits;
import std.algorithm;
import std.datetime;
import std.stdio;
import std.bitmanip;   // endianness stuff

enum fpdfVersion = 1.7;

float[2][string] StdPageSizes;

//----------------------------------------------------------------------------

shared static this()
{
  StdPageSizes = 
  [
    "a3" : [ 841.89, 1190.55 ],
    "a4" : [ 595.28, 841.89 ],
    "a5" : [ 420.94, 595.28 ],
    "letter" : [ 612.0, 792.0 ],
    "legal" : [ 612.0, 1008.0 ],
  ];
}

/****************************************************************************
 * class Fpdf
 ****************************************************************************/

//----------------------------------------------------------------------------
class Fpdf
//----------------------------------------------------------------------------
{
  struct LinkInfo
  {
    float x,y,w,h;
    ulong link;
    string externalLink;
  }
  struct LinkDest
  {
    ulong page;
    float y;
  }

  struct ImageInfo
  {
    ulong i,n;
    ulong w,h;
    string cs;  // Color space
    uint bpc; // Bits per component.
    string f; // Filter
    string dp; // DecodeParams
    string pal; // Palette
    ubyte[] trns; // transparency
    ubyte[] data;
    ubyte[] smask;
  }

  protected:
    ulong page = 0;
    ulong n = 2;
    ulong[] offsets;
    Appender!string buffer;

    uint state = 0;                // current document state

    Appender!(string)[ulong] pages;     // array containing pages
    bool compress = true;                 // compression flag
    float k;                       // scale factor (number of points in user unit)
    char DefOrientation;    // default orientation
    char CurOrientation;    // current orientation
    float[2] DefPageSize;          // default page size
    float[2] CurPageSize;          // current page size
    float[2][ulong] PageSizes;             // used for pages with non default sizes or orientations
    float wPt, hPt;                // dimensions of current page in points
    float w, h;                    // dimensions of current page in user unit
    float lMargin;                 // left margin
    float tMargin;                 // top margin
    float rMargin;                 // right margin
    float bMargin;                 // page break margin
    float cMargin;                 // cell margin
    float x, y;                    // current position in user unit
    float lasth;                   // height of last printed cell
    float LineWidth;               // line width in user unit
    string fontpath;               // path containing fonts
    string[] CoreFonts;            // array of core font names
    FontFileInfo[string] FontFiles;            // array of font files
    string[] diffs;                // array of encoding differences
    string FontFamily;             // current font family
    string FontStyle;              // current font style
    bool underline;                // underlining flag
    FontInfo CurrentFont;          // current font info
    float FontSizePt = 12.0;       // current font size in points
    float FontSize;                // current font size in user unit
    string DrawColor;              // commands for drawing color
    string FillColor;              // commands for filling color
    string TextColor;              // commands for text color
    bool ColorFlag;                // indicates whether fill and text colors are different
    float ws = 0.0;                // word spacing
    LinkInfo[][ulong] PageLinks;     // array of links in pages
    LinkDest[] links;                  // array of internal links
    bool AutoPageBreak;            // automatic page breaking
    float PageBreakTrigger;        // threshold used to trigger page breaks
    bool InHeader;                 // flag set when processing header
    bool InFooter;                 // flag set when processing footer
    string zoomMode;               // zoom display mode
    float zoom = 0;                // numeric zoom
    string layoutMode;         // layout display mode
    string title;                  // title
    string subject;                // subject
    string author;                 // author
    string[] keywords;             // keywords
    string creator;                // creator
    string aliasNbPages;           // alias for total number of pages
    float pdfVersion;             // PDF version number

    // Image files;
    ImageInfo[] images;
    ulong[string] imageInfoIdx;

    // Fonts
    FontInfo[] fonts;
    ulong[string] fontInfoIdx;

  public:

  //-----------------------------------

  private void setUnit(string unit)
  {
    // Scale factor;
    switch (unit)
    {
      case "pt": k = 1; break;
      case "mm": k = 72/25.4; break;
      case "cm": k = 72/2.54; break;
      case "in": k = 72; break;
      default: throw new Exception("Unknown unit");
    }
  }

  //-----------------------------------

  this(char orientation = 'P', string unit = "mm", string size = "a4")
  {
    setUnit(unit);
    setup(orientation, _getpagesize(size));
  }

  this(char orientation, string unit, float[2] sz)
  {
    setUnit(unit);
    setup(orientation, _getpagesize(sz));
  }

  //-----------------------------------

  private void setup(char orientation, float[2] sz)
  {
    n = 2;
    buffer = appender!string();
    DrawColor = "0 G";
    FillColor = "0 g";
    TextColor = "0 g";

    // Font path
    static if (__traits(compiles, fpdfFontPath))
    {
      fontpath = fpdfFontPath;
      if (fontpath[$-1] != '/' && fontpath[$-1] != '\\')
        fontpath ~= "/";
    }

    // Core fonts
    CoreFonts = [ "courier", "helvetica", "times", "symbol", "zapfdingbats" ];

    DefPageSize = sz;
    CurPageSize = sz;

    // Page Orientation
    if (orientation == 'P')
    {
      w = sz[0];
      h = sz[1];
    }
    else if (orientation == 'L')
    {
      w = sz[1];
      h = sz[0];
    }
    else
      throw new Exception("Unkown orientation");

    DefOrientation = orientation;
    CurOrientation = orientation;
    wPt = w*k;
    hPt = h*k;

    // Margins
    auto margin = 28.35/k; // 1cm
    SetMargins(margin,margin);
    cMargin = margin/10; // 1mm
    LineWidth = 0.567/k; // 0.2mm
    SetAutoPageBreak(true, 2*margin);

    pdfVersion = 1.3;
  }

  void SetMargins(float left, float top, float right = -1)
  {
    lMargin = left;
    tMargin = top;
    if (right < 0)
      rMargin = left;
    else
      rMargin = right;
  }

  void SetLeftMargin(float margin)
  {
    lMargin = margin;
    if (page > 0 && x < margin)
     x = margin;
  }

  void SetTopMargin(float margin)
  {
    // Set top margin
    tMargin = margin;
  }

  void SetRightMargin(float margin)
  {
    // Set right margin
    rMargin = margin;
  }

  void SetAutoPageBreak(bool isAuto, float margin=0)
  {
    // Set auto page break mode and triggering margin
    AutoPageBreak = isAuto;
    bMargin = margin;
    PageBreakTrigger = h-margin;
  }

  void SetDisplayMode(string zoom, string layout="default")
  {
    // Set display mode in viewer
    if (zoom!="fullpage" && zoom!="fullwidth" && zoom!="real" && zoom!="default")
      throw new Exception("Incorrect zoom display mode "~ zoom);
    if(layout!="single" && layout!="continuous" && layout!="two" && layout!="default")
      throw new Exception("Incorrect layout display mode: "~layout);
    zoomMode = zoom;
    this.zoom = 0;
    layoutMode = layout;
  }

  void SetDisplayMode(float zoom, string layout="default")
  {
    // Set display mode in viewer
    if(layout!="single" && layout!="continuous" && layout!="two" && layout!="default")
      throw new Exception("Incorrect layout display mode: "~layout);
    zoomMode = "custom";
    this.zoom = zoom;
    layoutMode = layout;
  }

  void SetCompression(bool compress)
  {
    // Set page compression TODO is compress available?
    this.compress = compress;
  }

  void SetTitle(string title)
  {
    // Title of document
    this.title = title;
  }

  void SetSubject(string subject)
  {
    // Subject of document
    this.subject = subject;
  }

  void SetAuthor(string author)
  {
    // Author of document
    this.author = author;
  }

  void SetKeywords(string[] keywords)
  {
    // Keywords of document
    this.keywords = keywords;
  }

  void SetCreator(string creator)
  {
    // Creator of document
    this.creator = creator;
  }

  void AliasNbPages(string nbAlias="{nb}")
  {
    // Define an alias for total number of pages
    aliasNbPages = nbAlias;
  }

  void Open()
  {
    // Begin document
    state = 1;
  }

  void Close()
  {
    // Terminate document
    if(state==3)
      return;
    if(page==0)
      AddPage();
    // Page footer
    InFooter = true;
    Footer();
    InFooter = false;
    // Close page
    _endpage();
    // Close document
    _enddoc();
  }

  //-----------------------------------

  void AddPage() { AddPage(DefOrientation, DefPageSize); }
  void AddPage(char orientation, string size = null)
  {
    if (size is null) AddPage(orientation, DefPageSize);
    else AddPage(orientation, _getpagesize(size));
  }

  void AddPage(char orientation, float[2] size)
  {
    // Start a new page
    if(state==0)
      Open();
    auto family = FontFamily;
    auto style = FontStyle ~ (underline ? "U" : "");
    auto fontsize = FontSizePt;
    auto lw = LineWidth;
    auto dc = DrawColor;
    auto fc = FillColor;
    auto tc = TextColor;
    auto cf = ColorFlag;
    if(page>0)
    {
      // Page footer
      InFooter = true;
      Footer();
      InFooter = false;
      // Close page
      _endpage();
    }

    // Start new page
    _beginpage(orientation,size);
    // Set line cap style to square
    _out("2 J");
    // Set line width
    LineWidth = lw;
    _out(format("%.2F w",lw*k));
    // Set font
    if(family)
      SetFont(family,style,fontsize);
    // Set colors
    DrawColor = dc;
    if (dc!="0 G")
      _out(dc);
    FillColor = fc;
    if(fc!="0 g")
      _out(fc);
    TextColor = tc;
    ColorFlag = cf;
    // Page header
    InHeader = true;
    Header();
    InHeader = false;
    // Restore line width
    if(LineWidth!=lw)
    {
      LineWidth = lw;
      _out(format("%.2F w",lw*k));
    }
    // Restore font
    if(family)
      SetFont(family,style,fontsize);
    // Restore colors
    if(DrawColor!=dc)
    {
      DrawColor = dc;
      _out(dc);
    }
    if(FillColor!=fc)
    {
      FillColor = fc;
      _out(fc);
    }
    TextColor = tc;
    ColorFlag = cf;
  }

  //-----------------------------------

  void Header()
  {
    // To be implemented in your own inherited class
  }

  void Footer()
  {
    // To be implemented in your own inherited class
  }

  //-----------------------------------

  ulong PageNo()
  {
    // Get current page number
    return page;
  }

  //-----------------------------------

  void SetDrawColor(ulong r)
  {
    // Set color for all stroking operations
    DrawColor = format("%.3F G",to!float(r)/255);
    if(page>0)
     _out(DrawColor);
  }
  
  void SetDrawColor(ulong r, ulong g, ulong b)
  {
    // Set color for all stroking operations
    DrawColor = format("%.3F %.3F %.3F RG",to!float(r)/255,to!float(g)/255,to!float(b)/255);
    if(page>0)
     _out(DrawColor);
  }

  void SetFillColor(ulong r)
  {
    // Set color for all filling operations
    FillColor = format("%.3F g",to!float(r)/255);
    ColorFlag = (FillColor!=TextColor);
    if(page>0)
      _out(FillColor);
  }

  void SetFillColor(ulong r, ulong g, ulong b)
  {
    // Set color for all filling operations
    FillColor = format("%.3F %.3F %.3F rg",to!float(r)/255,to!float(g)/255,to!float(b)/255);
    ColorFlag = (FillColor!=TextColor);
    if(page>0)
      _out(FillColor);
  }

  void SetTextColor(ulong r)
  {
    TextColor = format("%.3F g",to!float(r)/255);
    ColorFlag = (FillColor!=TextColor);
  }

  void SetTextColor(ulong r, ulong g, ulong b)
  {
    TextColor = format("%.3F %.3F %.3F rg",to!float(r)/255,to!float(g)/255,to!float(b)/255);
    ColorFlag = (FillColor!=TextColor);
  }

  float GetStringWidth(string s)
  {
    // Get width of a string in the current font
    auto cw = CurrentFont.cw;
    float w = 0;

    for (auto i=0; i<s.length; ++i) // TODO check for UTF issues
      w += cw[s[i]];
    return w*FontSize/1000;
  }

  void SetLineWidth(float width)
  {
    // Set line width
    LineWidth = width;
    if (page>0)
      _out(format("%.2F w",width*k));
  }

  void Line(float x1, float y1, float x2, float y2)
  {
    // Draw a line
    _out(format("%.2F %.2F m %.2F %.2F l S",x1*k,(h-y1)*k,x2*k,(h-y2)*k));
  }

  void Rect(float x, float y, float w, float h, string style="")
  {
    char op;
    // Draw a rectangle
    if(style=="F")
      op = 'f';
    else if (style=="FD" || style=="DF")
      op = 'B';
    else
      op = 'S';
    _out(format("%.2F %.2F %.2F %.2F re %c",x*k,(h-y)*k,w*k,-h*k,op));
  }

  void AddFont(string family, string style, string file)
  {
/+
    // Add a TrueType, OpenType or Type1 font
    family = toLower(family);
    style = toUpper(style);
    if (style=="IB")
      style = "BI";
    auto fontkey = family ~ style;
    if (fontkey in fonts)
      return;
    auto info = _loadfont(file);
    info.i = fonts.length+1;
    if(!info.diff.empty)
    {
      long n = -1;
      // Search existing encodings
      for (auto i=0; i< diffs.length; ++i)
        if (diffs[i] == info.diff)
        { n = i; break; }
          
      if(n<0)
      {
        n = diffs.length+1;
        diffs[n] = info.diff;
      }
      info.diffn = n;
    }
    if(!info.file.empty)
    {
      // Embedded font
      if(info.type=="TrueType")
        FontFiles[info.file] = FontFileInfo(info.originalsize);
      else
        FontFiles[info.file] = FontFileInfo(info.size1, info.size2);
    }
    fonts[fontkey] = info;
+/
  }

  void SetFont(string family, string style=null, float size=0)
  {

    // Select a font; size given in points
    if (family.empty)
      family = FontFamily;
    else
      family = toLower(family);
    style = toUpper(style);
    if(indexOf(style,'U') != -1)
    {
      underline = true;
      style = replace(style,"U","");
    }
    else
      underline = false;
    if (style=="IB")
      style = "BI";
    if (size==0)
      size = FontSizePt;
    // Test if font is already selected
    if (FontFamily==family && FontStyle==style && FontSizePt==size)
      return;
    // Test if font is already loaded
    auto fontkey = family~style;
    if(!(fontkey in fontInfoIdx))
    {
      // Test if one of the core fonts
      if(family=="arial")
        family = "helvetica";
      if(canFind(CoreFonts, family))
      {
        if(family=="symbol" || family=="zapfdingbats")
          style = "";
        fontkey = family~style;
        if(!(fontkey in fontInfoIdx))
        {
          FontInfo info = cast(FontInfo) coreFonts[fontkey];
          fontInfoIdx[fontkey] = fonts.length;
          info.i = fonts.length+1;
          fonts ~= info;
        }
      }
      else
        throw new Exception("Undefined font: "~family~" "~style);
    }
    // Select it
    FontFamily = family;
    FontStyle = style;
    FontSizePt = size;
    FontSize = size/k;
    CurrentFont = fonts[fontInfoIdx[fontkey]];
    if(page>0)
      _out(format("BT /F%d %.2F Tf ET",CurrentFont.i,FontSizePt));
  }

  //---------------------------------

  void SetFontSize(float size)
  {
    // Set font size in points
    if(FontSizePt==size)
      return;
    FontSizePt = size;
    FontSize = size/k;
    if(page>0)
      _out(format("BT /F%d %.2F Tf ET",CurrentFont.i,FontSizePt));
  }

  //---------------------------------

  ulong AddLink()
  {
    // Create a new internal link
    links ~= LinkDest(0, 0);
    return links.length;
  }

  //---------------------------------

  void SetLink(ulong link, float y=-1, ulong page=0)
  {
    // Set destination of internal link
    if (y==-1)
      y = this.y;
    if(page==0)
      page = this.page;
    links[link-1] = LinkDest(page, y);
  }

  //---------------------------------

  void Link(float x, float y, float w, float h, ulong link)
  {
    // Put a link on the page
    PageLinks[page] ~= LinkInfo(x*k, hPt-y*k, w*k, h*k, link);
  }

  //---------------------------------

  void Link(float x, float y, float w, float h, string link)
  {
    // Put a link on the page
    PageLinks[page] ~= LinkInfo(x*k, hPt-y*k, w*k, h*k, 0, link);
  }

  //---------------------------------

  void Text(float x, float y, string txt)
  {
    // Output a string
    auto s = format("BT %.2F %.2F Td (%s) Tj ET",x*k,(h-y)*k,_escape(txt));
    if (underline && !txt.empty)
      s ~= " " ~_dounderline(x,y,txt);
    if (ColorFlag)
      s = "q "~TextColor~" "~s~" Q";
    _out(s);
  }

  //---------------------------------
  
  bool AcceptPageBreak()
  {
    // Accept automatic page break or not
    return AutoPageBreak;
  }

  //---------------------------------

  void Cell(float w, float h, string txt, string border, ulong ln, string algn, bool fill, ulong link)
  {
    auto dx = _cell(w, h, txt, border, ln, algn, fill);
    if (!link.empty && !txt.empty)
      Link(this.x+dx,this.y+.5*h-.5*FontSize,GetStringWidth(txt),FontSize,link);
  }

  void Cell(float w, float h=0, string txt="", string border="0", ulong ln=0, string algn="", bool fill=false, T link=null)
  {
    auto dx = _cell(w, h, txt, border, ln, algn, fill);
    if (!link.empty && !txt.empty)
      Link(this.x+dx,this.y+.5*h-.5*FontSize,GetStringWidth(txt),FontSize,link);
  }

  private float _cell(float w, float h, string txt, string border, ulong ln, string algn, bool fill)
  {
    // Output a cell

    if(y+h>PageBreakTrigger && !InHeader && !InFooter && AcceptPageBreak())
    {
      // Automatic page break
      auto x = this.x;
      auto ws = this.ws;
      if (ws>0)
      {
        this.ws = 0;
        _out("0 Tw");
      }
      AddPage(CurOrientation,CurPageSize);
      this.x = x;
      if (ws>0)
      {
        this.ws = ws;
        _out(format("%.3F Tw",ws*k));
      }
    }
    if (w==0)
      w = this.w - rMargin - this.x;
    auto s = "";
    string op;
    if (fill || border=="1")
    {
      if (fill)
        op = (border=="1") ? "B" : "f";
      else
        op = "S";
      s = format("%.2F %.2F %.2F %.2F re %s ",this.x*k,(this.h-this.y)*k,w*k,-h*k,op);
    }

    if (indexOf(border,'L')!=-1)
      s ~= format("%.2F %.2F m %.2F %.2F l S ",x*k,(this.h-y)*k,x*k,(this.h-(y+h))*k);
    if (indexOf(border,'T')!=-1)
      s ~= format("%.2F %.2F m %.2F %.2F l S ",x*k,(this.h-y)*k,(x+w)*k,(this.h-y)*k);
    if (indexOf(border,'R')!=-1)
      s ~= format("%.2F %.2F m %.2F %.2F l S ",(x+w)*k,(this.h-y)*k,(x+w)*k,(this.h-(y+h))*k);
    if (indexOf(border,'B')!=-1)
      s ~= format("%.2F %.2F m %.2F %.2F l S ",x*k,(this.h-(y+h))*k,(x+w)*k,(this.h-(y+h))*k);

    float dx;

    if (!txt.empty)
    {
      if(algn=="R")
        dx = w-cMargin-GetStringWidth(txt);
      else if (algn=="C")
        dx = (w-GetStringWidth(txt))/2;
      else
        dx = cMargin;
      if (ColorFlag)
       s ~= "q "~TextColor~" ";
      auto txt2 = txt.replace("\\","\\\\").replace(")","\\)").replace("(","\\(",);
      s ~= format("BT %.2F %.2F Td (%s) Tj ET",(x+dx)*k,(this.h-(this.y+0.5*h+0.3*FontSize))*k,txt2);
      if (underline)
      s ~= " "~_dounderline(x+dx,y+0.5*h+0.3*FontSize,txt);
      if (ColorFlag)
        s ~= " Q";
    }
    if(s)
      _out(s);
    lasth = h;
    if (ln>0)
    {
      // Go to next line
      y += h;
      if (ln==1)
        this.x = lMargin;
    }
    else
      this.x += w;

    return dx;
  }

  //-----------------------------------

  void MultiCell(float w, float h, string txt,  string border="0", string algn="J", bool fill=false)
  {
    // Output text with automatic or explicit line breaks
    auto cw = CurrentFont.cw;
    if(w==0)
      w = this.w-rMargin-x;
    auto wmax = (w-2*cMargin)*1000/FontSize;
    auto s = txt.replace("\r", "");
    auto nb = s.length;
    if(nb>0 && s[nb-1]=='\n')
      nb--;
    string b = null;
    string b2= null;
    if (border)
    {
      if(border=="1")
      {
        border = "LTRB";
        b = "LRT";
        b2 = "LR";
      }
      else
      {
        b2 = "";
        if(indexOf(border,'L')!=-1)
          b2 ~= "L";
        if(indexOf(border,'R')!=-1)
          b2 ~= "R";
        b = (indexOf(border,'T')!=-1) ? b2~"T" : b2;
      }
    }
    auto sep = -1;
    auto i = 0;
    auto j = 0;
    auto l = 0;
    auto ns = 0;
    auto nl = 1;
    auto ls = 0;

    while(i<nb)
    {
      // Get next character
      auto c = s[i];
      if(c=='\n')
      {
        // Explicit line break
        if(ws>0)
        {
          ws = 0;
          _out("0 Tw");
        }
        Cell(w,h,s[j..i],b,2,algn,fill);
        i++;
        sep = -1;
        j = i;
        l = 0;
        ns = 0;
        nl++;
        if(border!="0" && nl==2)
          b = b2;
        continue;
      }
      if(c==' ')
      {
        sep = i;
        ls = l;
        ns++;
      }
      l += cw[c];
      if(l>wmax)
      {
        // Automatic line break
        if(sep==-1)
        {
          if(i==j)
            i++;
          if(ws>0)
          {
            ws = 0;
            _out("0 Tw");
          }
          Cell(w,h,s[j..i],b,2,algn,fill);
        }
        else
        {
          if(algn=="J")
          {
            ws = (ns>1) ? (wmax-ls)/1000*FontSize/(ns-1) : 0;
            _out(format("%.3F Tw",ws*k));
          }
          Cell(w,h,s[j..sep],b,2,algn,fill);
          i = sep+1;
        }
        sep = -1;
        j = i;
        l = 0;
        ns = 0;
        nl++;
        if(border!="0" && nl==2)
          b = b2;
      }
      else
        i++;
    }
    // Last chunk
    if(ws>0)
    {
      ws = 0;
      _out("0 Tw");
    }
    if(indexOf(border,"B")!=-1)
      b ~= "B";
    Cell(w,h,s[j..i],b,2,algn,fill);
    x = lMargin;
  }

  //-----------------------------------

  // TODO improve link.

  void Write(float h, string txt, string link=null)
  {
    // Output text in flowing mode
    auto cw = CurrentFont.cw;
    auto w = this.w-rMargin-x;
    auto wmax = (w-2*cMargin)*1000/FontSize;
    auto s = txt.replace("\r","");
    auto nb = s.length;
    auto sep = -1;
    auto i = 0;
    auto j = 0;
    auto l = 0;
    auto nl = 1;
    while(i<nb)
    {
      // Get next character
      auto c = s[i];
      if(c=='\n')
      {
        // Explicit line break
        Cell(w,h,s[j..i],"0",2L,"",false,link);
        i++;
        sep = -1;
        j = i;
        l = 0;
        if(nl==1)
        {
          x = lMargin;
          w = this.w-rMargin-x;
          wmax = (w-2*cMargin)*1000/FontSize;
        }
        nl++;
        continue;
      }
      if(c==' ')
      sep = i;
      l += cw[c];
      if (l>wmax)
      {
        // Automatic line break
        if(sep==-1)
        {
          if(x>lMargin)
          {
            // Move to next line
            x = lMargin;
            y += h;
            w = w-rMargin-x;
            wmax = (w-2*cMargin)*1000/FontSize;
            i++;
            nl++;
            continue;
          }
          if(i==j)
            i++;
          Cell(w,h,s[j..i],"0",2L,"",false,link);
        }
        else
        {
          Cell(w,h,s[j..sep],"0",2L,"",false,link);
          i = sep+1;
        }
        sep = -1;
        j = i;
        l = 0;
        if(nl==1)
        {
          x = lMargin;
          w = this.w-rMargin-x;
          wmax = (w-2*cMargin)*1000/FontSize;
        }
        nl++;
      }
      else
        i++;
    }
    // Last chunk
    if(i!=j)
      Cell(l/1000*FontSize,h,s[j..$],"0",0L,"",false,link);
  }

  void Ln()
  {
    Ln(lasth);
  }

  void Ln(float h)
  {
    // Line feed; default value is last cell height
    x = lMargin;
    y += h;
  }

  //-----------------------------------

  struct Rect
  {
    float x,y,w,h;
  }

  void Image(string file, float x, float y, float w, float h, string type, ulong link)
  {
    auto r = _image(file, x, y, w, h, type);
    if(!link.empty)
      Link(r.x,r.y,r.w,r.h,link);
  }

  void Image(string file, float x=-1, float y=-1, float w=0, float h=0, string type=null, string link=null)
  {
    auto r = _image(file, x, y, w, h, type);
    if(!link.empty)
      Link(r.x,r.y,r.w,r.h,link);
  }

  private Rect _image(file, float x, float y, float w, float h, string type)
  {

    // Put an image on the page
    ImageInfo info;

    if(!(file in imageInfoIdx))
    {
      // First use of this image, get info
      if (type.empty)
      {
        auto pos = indexOf(file,'.');
        if(pos <=0)
          throw new Exception("Image file has no extension and no type was specified: "~file);
        type = file[pos+1..$];
      }
      
      switch (toLower(type))
      {
        case "jpeg":
        case "jpg":
          info = _parsejpg(file);
          break;
        case "png":
          info = _parsepng(file);
          break;
        default:
          throw new Exception("Unsupported image type: "~type);
      }
      auto l = images.length;
      imageInfoIdx[file] = l;
      info.i = l+1;
      images ~= info;
    }
    else
      info = images[imageInfoIdx[file]];

    // Automatic width and height calculation if needed
    if (w==0 && h==0)
    {
      // Put image at 96 dpi
      w = -96;
      h = -96;
    }
    if(w<0)
      w = -to!float(info.w)*72/w/k;
    if(h<0)
      h = -to!float(info.h)*72/h/k;
    if(w==0)
      w = h*to!float(info.w)/to!float(info.h);
    if(h==0)
      h = w*to!float(info.h)/to!float(info.w);

    // Flowing mode
    if(y<0)
    {
      if(this.y+h>PageBreakTrigger && !InHeader && !InFooter && AcceptPageBreak())
      {
        // Automatic page break
        auto x2 = this.x;
        AddPage(CurOrientation,CurPageSize);
        this.x = x2;
      }
      y = this.y;
      this.y += h;
    }

    if(x<0)
      x = this.x;
    _out(format("q %.2F 0 0 %.2F %.2F %.2F cm /I%d Do Q", w*k, h*k, x*k, (this.h-(y+h))*k, info.i));

    auto r = Rect(x,y,w,h);
    return r;
  }

  //-----------------------------------

  float GetX()        { return x; }
  void  SetX(float x) { this.x = (x>=0)? x : w+x; }
  float GetY()        { return y; }
  void  SetY(float y) { x = lMargin; this.y = (y >= 0) ? y : h+y; }

  //-----------------------------------

  void SetXY(float x, float y)
  {
    // Set x and y positions
    SetY(y);
    SetX(x);
  }

  //-----------------------------------

  string Output()
  {
    if(state<3)
      Close();
    return buffer.data;
  }

  //------------------------------------------------------------
  // Protected methods

  protected:

    float[2] _getpagesize(string size)
    {
      size = toLower(size);
      if(!(size in StdPageSizes))
        throw new Exception("Unknown page size: "~size);
      auto a = StdPageSizes[size];
      return [ a[0]/k, a[1]/k ];
    }

    float[2] _getpagesize(float[2] size)
    {
      if(size[0]>size[1])
        return [ size[1], size[0] ];
      else
        return size;
    }

    //---------------------------------

    void _beginpage(char orientation, float[2] size)
    {
      ++page;
      pages[page] = appender!string();
      state = 2;
      x = lMargin;
      y = tMargin;
      FontFamily = "";
      // Check page size and orientation
      if (orientation!=CurOrientation || size[0]!=CurPageSize[0] || size[1]!=CurPageSize[1])
      {
        // New size or orientation
        if(orientation=='P')
        {
          w = size[0];
          h = size[1];
        }
        else
        {
          w = size[1];
          h = size[0];
        }
        wPt = w*k;
        hPt = h*k;
        PageBreakTrigger = h-bMargin;
        CurOrientation = orientation;
        CurPageSize = size;
      }
      if(orientation!=DefOrientation || size[0]!=DefPageSize[0] || size[1]!=DefPageSize[1])
        PageSizes[page] = [ wPt, hPt ];
    }

    //---------------------------------

    void _endpage()
    {
      state = 1;
    }

    //---------------------------------

/+
    FontInfo _loadfont(string file)
    {
      // Reads a font definition from a JSON file. (Note different from original).
      FontInfo info;
      auto raw = readText(file);

      auto decoded = parseJSON(raw);
      auto tLvl = decoded.object;
      info.type = tLvl["type"].str;
      info.name = tLvl["num"].str;
      info.up = tLvl["up"].integer;
      info.ut = tLvl["ut"].integer;
      info.cw.length = tLvl["cw"].array.length;
      foreach(x; tLvl["cw"].array)
        info.cw ~= x.uinteger;
      return info;
    }
+/

    string _escape(string s)
    {
      // Escape special characters in strings
      return s.replace("\\","\\\\")
              .replace("(","\\(")
              .replace(")","\\)")
              .replace("\r","\\r");
    }

    string _textstring(string s)
    {
      // Format a text string
      return "("~_escape(s)~")";
    }

    string _dounderline(float x, float y, string txt)
    {
      // Underline text
      auto up = CurrentFont.up;
      auto ut = CurrentFont.ut;
      auto w = GetStringWidth(txt)+ws*txt.length;
      return format("%.2F %.2F %.2F %.2F re f",x*k,(h-(y-up/1000*FontSize))*k,w*k,-ut/1000*FontSizePt);
    }

    ImageInfo _parsejpg(string file)
    {
      // Extract info from a JPEG file
      ImageInfo info;

      info.data = cast(ubyte[]) read(file);
      auto ifImage = read_jpeg_from_mem(info.data);

      info.w = ifImage.w;
      info.h = ifImage.h;
      switch(ifImage.c)
      {
        case ColFmt.Y:
          info.cs = "DeviceGray";
          break;
        case ColFmt.RGB:
          info.cs = "DeviceRGB";
          break;
        default: break;
      }
      info.bpc = 8; // something about bits?
      info.f = "DCTDecode";
      return info;
    }


    ImageInfo _parsepng(string filename)
    {
      // Extract info from a PNG file

      ImageInfo info;

      File file;
      file.open(filename);
      scope(exit) { file.close(); }

      auto sig = _readstream(file, 8);
      if (sig != [ 137, 'P','N','G', 13,10,26,10 ])
        throw new Exception("Not a PNG file");

      _readstream(file, 4);
      if (_readstream(file, 4) != cast(ubyte[]) "IHDR")
        throw new Exception("Unsupported PNG type");

      info.w = _readint(file);
      info.h = _readint(file);
      info.bpc = _readstream(file,1)[0];
      auto ct = _readstream(file,1)[0];
      switch (ct)
      {
        case 0:
        case 4:
          info.cs = "DeviceGrey";
          break;
        case 2:
        case 6:
          info.cs = "DeviceRGB";
          break;
        case 3:
          info.cs = "Indexed";
          break;
        default:
          throw new Exception("Unknown color type");
      }
      auto compMethod = _readstream(file,1)[0];
      auto filterMethod = _readstream(file,1)[0];
      auto interlaceMethod = _readstream(file,1)[0];
      _readstream(file, 4);

      info.dp = "/Predictor 15 /Colors "~(info.cs=="DeviceRGB" ? "3" : "1")~" /BitsPerComponent "~to!string(info.bpc)~" /Columns "~to!string(info.w);
      info.f = "FlateDecode";

	// Scan chunks looking for palette, transparency and image data
      ubyte[] pal, data = [];

      auto finish = false;
      do
      {
        auto n = _readint(file);
        string type = cast(string) _readstream(file,4);
        switch (type)
        {
          case "PLTE":
            // Read palette
            pal = _readstream(file,n);
            _readstream(file,4);
            break;
          case "tRNS":
            // Read transparency info
            auto t = _readstream(file,n);
            if(ct == 0)
              info.trns = t[1..2];
            else if(ct == 2)
              info.trns = [ t[1], t[3], t[5] ];
            else
            {
              auto pos = indexOf(cast(string)t, '\0');
              if (pos != -1)
                info.trns = [ cast(ubyte)pos ];
            }
            _readstream(file,4);
            break;
          case "IDAT":
            data ~= _readstream(file,n);
            _readstream(file,4);
            break;
          case "IEND":
            finish = true;
            break;
          default:
            _readstream(file,n+4);
        }
      } while (!finish);

      if (ct >= 4)
      {
        auto color = appender!(ubyte[])();
        auto alpha = appender!(ubyte[])();
        data = cast(ubyte[]) uncompress(data);

        if (ct == 4)
        {
          // Extract alpha imformation from Gray image
          auto len = 2*info.w;

          for(auto i=0;i<info.h;++i)
          {
            auto pos = (1+len)*i;
            color.put(data[pos]);
            alpha.put(data[pos]);
            auto line = data[pos+1..pos+1+len];
            for (auto j=0; j<line.length; j+=2)
            {
              color.put(line[j]);
              alpha.put(line[j+1]);
            }
          }
        }
        else
        {
          // Extract alpha imformation from RGB image
          auto len = 4*info.w;
          for(auto i=0;i<info.h;++i)
          {
            auto pos = (1+len)*i;
            color.put(data[pos]);
            alpha.put(data[pos]);
            auto line = data[pos+1..pos+1+len];
            for (auto j=0; j<line.length; j+=4)
            {
              color.put(line[j..j+3]);
              alpha.put(line[j+3]);
            }
          }
        }

        info.data = cast(ubyte[]) .compress(color.data);
        info.smask = cast(ubyte[]) .compress(alpha.data);
        if(pdfVersion<1.4)
          pdfVersion = 1.4;
      }
      else
        info.data = data;
      return info;
    }


    ubyte[] _readstream(ref File f, uint n)
    {
      ubyte[] buffer;
      buffer.length = n;

      return f.rawRead(buffer);
    }

    uint _readint(ref File f)
    {
      return bigEndianToNative!uint(_readstream(f,4)[0..4]);
    }

void _parsegif(string file)
{
}

    void _newobj()
    {
      // Begin a new object
      ++n;
      offsets.length = n+1;
      offsets[n] = buffer.data.length;
      _out(to!string(n)~" 0 obj");
    }

    void _putstream(string s)
    {
      _out("stream");
      _out(s);
      _out("endstream");
    }

    //---------------------------------

    void _out(string s)
    {
      // Add a line to the document
      if(state==2)
      {
        pages[page].put(s);
        pages[page].put("\n");
      }
      else
      {
        buffer.put(s);
        buffer.put("\n");
      }
    }

    //---------------------------------

    void _putpages()
    {
      auto nb = page;

      if(DefOrientation=='P')
      {
        wPt = DefPageSize[0]*k;
        hPt = DefPageSize[1]*k;
      }
      else
      {
        wPt = DefPageSize[1]*k;
        hPt = DefPageSize[0]*k;
      }
      auto filter = (compress) ? "/Filter /FlateDecode " : "";
      for(auto n=1;n<=nb;n++)
      {
        // Page
        _newobj();
        _out("<</Type /Page");
        _out("/Parent 1 0 R");
        if(n in PageSizes)
          _out(format("/MediaBox [0 0 %.2F %.2F]",PageSizes[n][0],PageSizes[n][1]));
        _out("/Resources 2 0 R");
        if(n in PageLinks)
        {
          // Links
          auto annots = "/Annots [";
          foreach(link; PageLinks[n])
          {
            auto rect = format("%.2F %.2F %.2F %.2F",link.x,link.y,link.x+link.w,link.y-link.h);
            annots ~= "<</Type /Annot /Subtype /Link /Rect ["~rect~"] /Border [0 0 0] ";
            if(!link.externalLink.empty) 
              annots ~= "/A <</S /URI /URI "~_textstring(link.externalLink)~">>>>";
            else
            {
              auto l = links[link.link-1];
              h = (l.page in PageSizes) ? PageSizes[l.page][1] : hPt;
              annots ~= format("/Dest [%d 0 R /XYZ 0 %.2F null]>>",1+2*l.page,h-l.y*k);
            }
          }
          _out(annots~"]");
        }
        if(pdfVersion>1.3)
          _out("/Group <</Type /Group /S /Transparency /CS /DeviceRGB>>");
        _out("/Contents "~.to!string(this.n+1)~" 0 R>>");
        _out("endobj");

        // Page content
        auto p = pages[n].data;
        if(!aliasNbPages.empty)
          p = p.replace(aliasNbPages,to!string(nb));
        _newobj();
        auto p2 = compress ? (cast(string) .compress(p)) : p;

        _out("<<"~filter~"/Length "~to!string(p2.length)~">>");
        _putstream(p2);
        _out("endobj");
      }
      // Pages root
      offsets[1] = buffer.data.length;
      _out("1 0 obj");
      _out("<</Type /Pages");
      auto kids = "/Kids [";
      for(auto i=0;i<nb;i++)
        kids ~= to!string(3+2*i)~" 0 R ";
      _out(kids~"]");
      _out("/Count "~to!string(nb));
      _out(format("/MediaBox [0 0 %.2F %.2F]",wPt,hPt));
      _out(">>");
      _out("endobj");
    }

    //---------------------------------

    void _putfonts()
    {
      auto nf = n;
      foreach(diff; diffs)
      {
        // Encodings
        _newobj();
        _out("<</Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences ["~diff~"]>>");
        _out("endobj");
      }/*
      foreach(file,info ; FontFiles)
      {
        // Font file embedding
        _newobj();
        FontFiles[file].n = n;
        auto font = readFile(fontpath~file);

        bool compressed = file[$-2..$]==".z");
        if(!compressed && info.length2 != 0))
          font = font[6,info.length1 ~ font[6+info.length1+6..info.length2];
        _out("<</Length "~to!string(font.length));
        if(compressed)
          _out("/Filter /FlateDecode");
        _out("/Length1 "~to!string(info.length2);
        if(info.length2 != 0)
          _out("/Length2 "~to!string(info.length2)~" /Length3 0");
        _out(">>");
        _putstream(font);
        _out("endobj");
      }*/
      foreach(ref font; fonts)
      {
        // Font objects
        font.n = n+1;
        auto type = font.type;
        auto name = font.name;
        if (type=="Core")
        {
          // Core font
          _newobj();
          _out("<</Type /Font");
          _out("/BaseFont /"~name);
          _out("/Subtype /Type1");
          if(name!="Symbol" && name!="ZapfDingbats")
            _out("/Encoding /WinAnsiEncoding");
          _out(">>");
          _out("endobj");
        }
        else if(type=="Type1" || type=="TrueType")
        {
          // Additional Type1 or TrueType/OpenType font
          _newobj();
          _out("<</Type /Font");
          _out("/BaseFont /"~name);
          _out("/Subtype /"~type);
          _out("/FirstChar 32 /LastChar 255");
          _out("/Widths "~to!string(n+1)~" 0 R");
          _out("/FontDescriptor "~to!string(n+2)~" 0 R");
          if(font.diffn != ulong.max)
            _out("/Encoding "~to!string(nf+font.diffn)~" 0 R");
          else
            _out("/Encoding /WinAnsiEncoding");
          _out(">>");
          _out("endobj");
          // Widths
          _newobj();
          auto s = appender!string; s.put("[");
          for(auto i=32;i<=255;i++)
          {
            s.put(to!string(font.cw[i]));
            s.put(" ");
          }
          s.put("]");
          _out(s.data);
          _out("endobj");
          // Descriptor
          _newobj();
          s= appender!string; s.put("<</Type /FontDescriptor /FontName /"); s.put(name);
          foreach(k,v; font.desc)
            s.put(" /"~k~" "~v);
          if (!font.file.empty)
            s.put(" /FontFile"~(type=="Type1" ? "" : "2")~" "~to!string(FontFiles[font.file].n)~" 0 R");
          _out(s.data~">>");
          _out("endobj");
        }
        else
        {
          throw new Exception("Unsupported font type: "~type);
        }
      }
    }

    //---------------------------------

    void _putimages()
    {
      foreach(ref info; images)
      {
        _putimage(info);
        info.data = info.data.init;
        info.smask = null;
      }
    }

    //---------------------------------

    void _putimage(ref ImageInfo info)
    {
      _newobj();
      info.n = n;
      _out("<</Type /XObject");
      _out("/Subtype /Image");
      _out("/Width "~to!string(info.w));
      _out("/Height "~to!string(info.h));
      if(info.cs=="Indexed")
        _out("/ColorSpace [/Indexed /DeviceRGB "~to!string(info.pal.length/3-1)~" "~to!string(n+1)~" 0 R]");
      else
      {
        _out("/ColorSpace /"~info.cs);
        if(info.cs=="DeviceCMYK")
          _out("/Decode [1 0 1 0 1 0 1 0]");
      }
      _out("/BitsPerComponent "~to!string(info.bpc));
      if(!info.f.empty)
        _out("/Filter /"~info.f);
      if(!info.dp.empty)
        _out("/DecodeParms <<"~info.dp~">>");

      if (!info.trns.empty)
      {
        auto trns = "";
        foreach (i; info.trns)
          trns ~= to!string(i)~" "~to!string(i)~" ";
        _out("/Mask ["~trns~"]");
	    }

      if (!info.smask.empty)
        _out("/SMask "~to!string(n+1)~" 0 R");

      _out("/Length "~to!string(info.data.length)~">>");
      _putstream(cast(string) info.data);
      _out("endobj");

      // Soft mask
      if (!info.smask.empty)
      {
        auto dp = "/Predictor 15 /Colors 1 /BitsPerComponent 8 /Columns "~to!string(info.w);
        auto smask = ImageInfo(0,0,info.w,info.h,"DeviceGray", 8, info.f, dp, null,null,info.smask);
        _putimage(smask);
      }

      // Palette
      if(info.cs=="Indexed")
      {
        auto filter = (compress) ? "/Filter /FlateDecode " : "";
        string pal = (compress) ? cast(string) .compress(info.pal) : info.pal;
        _newobj();
        _out("<<"~filter~"/Length "~to!string(pal.length)~">>");
        _putstream(pal);
        _out("endobj");
      }
    }

    //---------------------------------

    void _putxobjectdict()
    {
      foreach(image; images)
        _out("/I"~to!string(image.i)~" "~to!string(image.n)~" 0 R");
    }

    //---------------------------------

    void _putresourcedict()
    {
      _out("/ProcSet [/PDF /Text /ImageB /ImageC /ImageI]");
      _out("/Font <<");
      foreach(font; fonts)
        _out("/F"~to!string(font.i)~" "~to!string(font.n)~" 0 R");
      _out(">>");
      _out("/XObject <<");
      _putxobjectdict();
      _out(">>");
    }

    //---------------------------------

    void _putresources()
    {
      _putfonts();
      _putimages();
      // Resource dictionary
      offsets[2] = buffer.data.length;
      _out("2 0 obj");
      _out("<<");
      _putresourcedict();
      _out(">>");
      _out("endobj");
    }

    //---------------------------------

    void _putinfo()
    {
      _out("/Producer "~_textstring("FPDF (for D) "~to!string(fpdfVersion)));
      if(!title.empty)
        _out("/Title "~_textstring(title));
      if(!subject.empty)
        _out("/Subject "~_textstring(subject));
      if(!author.empty)
        _out("/Author "~_textstring(author));
      if(!keywords.empty)
        _out("/Keywords "~_textstring(keywords.join(",")));
      if(!creator.empty)
        _out("/Creator "~_textstring(creator));

      auto time = Clock.currTime.toISOString().replace("T","");
      auto dot = indexOf(time, ".");
      if (dot == -1) dot = time.length;
      _out("/CreationDate "~_textstring("D:"~time[0..dot]));
    }

    //---------------------------------

    void _putcatalog()
    {
      _out("/Type /Catalog");
      _out("/Pages 1 0 R");
      if(zoomMode=="fullpage")
        _out("/OpenAction [3 0 R /Fit]");
      else if(zoomMode=="fullwidth")
        _out("/OpenAction [3 0 R /FitH null]");
      else if(zoomMode=="real")
        _out("/OpenAction [3 0 R /XYZ null null 1]");
      else if(zoomMode == "custom")
        _out("/OpenAction [3 0 R /XYZ null null "~format("%.2F",zoom/100)~"]");
      if(layoutMode=="single")
        _out("/PageLayout /SinglePage");
      else if(layoutMode=="continuous")
        _out("/PageLayout /OneColumn");
      else if(layoutMode=="two")
        _out("/PageLayout /TwoColumnLeft");
    }

    //---------------------------------

    void _putheader()
    {
      _out("%PDF-"~to!string(pdfVersion));
    }

    //---------------------------------

    void _puttrailer()
    {
      _out("/Size "~to!string(n+1));
      _out("/Root "~to!string(n)~" 0 R");
      _out("/Info "~to!string(n-1)~" 0 R");
    }

    //---------------------------------

    void _enddoc()
    {
      _putheader();
      _putpages();
      _putresources();
      // Info
      _newobj();
      _out("<<");
      _putinfo();
      _out(">>");
      _out("endobj");
      // Catalog
      _newobj();
      _out("<<");
      _putcatalog();
      _out(">>");
      _out("endobj");
      // Cross-ref
      auto o = buffer.data.length;
      _out("xref");
      _out("0 "~to!string(n+1));
      _out("0000000000 65535 f ");
      for(auto i=1;i<=n;i++)
        _out(format("%010d 00000 n ",offsets[i]));
      // Trailer
      _out("trailer");
      _out("<<");
      _puttrailer();
      _out(">>");
      _out("startxref");
      _out(to!string(o));
      _out("%%EOF");
      state = 3;
    }

    //---------------------------------
}
