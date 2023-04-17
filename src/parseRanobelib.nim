import httpclient, uri, strutils, json, algorithm, strtabs, base64, os, sequtils, strformat
import localize, fusion/htmlparser, fusion/htmlparser/xmltree, argparse, filetype

type
  Chapter = object
    name, number: string
    volume: int

  ChapterContentKind = enum
    cckText, cckImage

  ChapterContentModifier = enum
    ccmNone, ccmBold, ccmItalic

  ChapterContent = object
    case kind: ChapterContentKind
    of cckText: text: string
    of cckImage: image: string

    modifier: ChapterContentModifier

  ChapterData = seq[ChapterContent]

requireLocalesToBeTranslated ("ru", "")

globalLocale = (systemLocale(), LocaleTable.default)

var logEnabled = true
template log*(s: string) =
  if logEnabled:
    echo s

var baseUrl = "https://ranobelib.me".parseUri

proc getHeading(name: string): string =
  log tr"Reading heading..."
  newHttpClient().get($(baseUrl/name?{"section": "chapters"})).body

proc getHtml*(ranobe: string, c: Chapter): string =
  log tr"Reading Volume {c.volume} Chapter {c.number}"
  newHttpClient().get($(baseUrl/ranobe / ("v" & $c.volume) / ("c" & c.number))).body

proc getImage*(link: string): string =
  log tr"Downloading image {link}"
  try:
    newHttpClient().get(link).body
  except:
    log tr"...Failed"
    ""


proc parseHeading(html: string): seq[Chapter] =
  let html = html.parseHtml
  proc findData(html: XmlNode): string =
    for x in html.findAll("script"):
      let x = x.innerText.strip
      if x.startsWith("window.__DATA__ = "):
        return x.splitLines[0]["window.__DATA__ = ".len..^2]
  let data = html.findData.parseJson
  for x in data["chapters"]["list"]:
    result.add Chapter(
      name: x["chapter_name"].to(string),
      number: x["chapter_number"].to(string),
      volume: x["chapter_volume"].to(int),
    )
  reverse result


proc parseChapter*(html: string, extractImages = true): ChapterData =
  let html = html.parseHtml
  proc findData(html: XmlNode): XmlNode =
    for x in html.findAll("div"):
      if x.attrs.hasKey("class") and ("reader-container" in x.attrs["class"].split):
        return x
  for x in html.findData:
    case x.htmlTag
    of tagP:
      var r = ChapterContent(
        kind: cckText,
        text: x.innerText,
      )
      if x.len > 0 and x[0].kind == xnElement and x[0].htmlTag == tagB:
        r.modifier = ccmBold
      if x.len > 0 and x[0].kind == xnElement and x[0].htmlTag == tagI:
        r.modifier = ccmItalic
      result.add r
    of tagDiv:
      if extractImages:
        if x.len > 0 and x[0].kind == xnElement and x[0].htmlTag == tagImg and x[0].attrs.hasKey("data-src"):
          result.add ChapterContent(
            kind: cckImage,
            image: x[0].attrs["data-src"].getImage,
          )
    else: discard


proc parseLink(s: string): string =
  if s.startsWith("http:") or s.startsWith("https:"):
    try:
      s.parseUri.path.split("/")[1]
    except IndexDefect:
      raise UsageError.newException("incorrect ranobe link")
  else:
    s


proc toHtml(c: ChapterData, injectImages = true): XmlNode =
  result = "body".newXmlTree([])
  for x in c:
    case x.kind
    of cckText:
      result.add "p".newXmlTree([
        case x.modifier
        of ccmNone: newText(x.text)
        of ccmBold: "b".newXmlTree([newText(x.text)])
        of ccmItalic: "i".newXmlTree([newText(x.text)])
      ])
    of cckImage:
      if injectImages:
        result.add "img".newXmlTree([], {"src": "data:" & cast[seq[byte]](x.image).match.mime.value & ";base64," & x.image.encode}.toXmlAttributes)
  result = "html".newXmlTree([result])


when isMainModule:
  template preprocess {.dirty.} =
    if opts.parentOpts.quiet: logEnabled = false

  var p = newParser:
    flag("-q", "--quiet", help="don't display logs")
    command("list"):
      help("list all ranobe chapters")
      arg("ranobe")
      run:
        preprocess

        let x = opts.ranobe.parseLink.getHeading.parseHeading
        for x in x:
          echo tr "Volume {x.volume}\tNumber {x.number}:\t{x.name}"

    command("html"):
      help("parse chapter / tome / whole manga and output html files")
      arg("ranobe")
      option("-o", "--output", help="set output file / directory")
      option("-v", "--volume", help="select volume")
      option("-c", "--chapter", help="select chapter")
      run:
        preprocess

        let ranobe = $opts.ranobe.parseLink
        if opts.volume != "" and opts.chapter != "":
          writeFile (if opts.output != "": opts.output else: "o.html"), $ranobe.getHtml(Chapter(volume: opts.volume.parseInt, number: opts.chapter)).parseChapter.toHtml
        else:
          var chapters = ranobe.getHeading.parseHeading
          if opts.volume != "":
            let volume = opts.volume.parseInt
            chapters = chapters.filterit(it.volume == volume)
          for c in chapters:
            try:
              writeFile (if opts.output != "": opts.output else: ".") / &"{c.volume}, {c.number}.html", $ranobe.getHtml(c).parseChapter.toHtml
            except:
              log tr"failed to download Volume {c.volume} Chapter {c.number}"


  try:
    run p
  except UsageError:
    stderr.writeLine getCurrentExceptionMsg()
    quit(1)

  updateTranslations()
