{.push raises: [].}

import std/options

import chame/tags
import html/catom
import html/dom
import html/domexception
import io/dynstream
import monoucha/fromjs
import monoucha/javascript
import monoucha/quickjs
import monoucha/tojs
import types/blob
import types/formdata
import types/opt
import utils/twtstr

proc constructEntryList*(form: HTMLFormElement; submitter: Element = nil;
    encoding = "UTF-8"): seq[FormDataEntry]

proc generateBoundary(urandom: PosixStream): string =
  var s {.noinit.}: array[33, uint8]
  doAssert urandom.readDataLoop(s)
  # 33 * 4 / 3 = 44 + prefix string is 22 bytes = 66 bytes
  return "----WebKitFormBoundary" & btoa(s)

proc newFormData0*(entries: sink seq[FormDataEntry]; urandom: PosixStream):
    FormData =
  return FormData(boundary: urandom.generateBoundary(), entries: entries)

proc newFormData(ctx: JSContext; form = none(HTMLFormElement);
    submitter = none(HTMLElement)): DOMResult[FormData] {.jsctor.} =
  let urandom = ctx.getGlobal().crypto.urandom
  let this = FormData(boundary: urandom.generateBoundary())
  if form.isSome:
    let form = form.get
    if submitter.isSome:
      let submitter = submitter.get
      if not submitter.isSubmitButton():
        return errDOMException("Submitter must be a submit button",
          "InvalidStateError")
      if FormAssociatedElement(submitter).form != form:
        return errDOMException("Submitter's form owner is not form",
          "InvalidStateError")
    if not form.constructingEntryList:
      this.entries = constructEntryList(form, submitter.get(nil))
  return ok(this)

proc append*(ctx: JSContext; this: FormData; name: string; val: JSValueConst;
    rest: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
  var blob: Blob
  if ctx.fromJS(val, blob).isOk:
    var filename = "blob"
    if rest.len > 0:
      ?ctx.fromJS(rest[0], filename)
    elif blob of WebFile:
      filename = WebFile(blob).name
    this.entries.add(FormDataEntry(
      name: name,
      isstr: false,
      value: blob,
      filename: filename
    ))
    ok()
  elif rest.len > 0:
    err()
  else:
    var s: string
    ?ctx.fromJS(val, s)
    this.entries.add(FormDataEntry(name: name, isstr: true, svalue: s))
    ok()

proc delete(this: FormData; name: string) {.jsfunc.} =
  for i in countdown(this.entries.high, 0):
    if this.entries[i].name == name:
      this.entries.delete(i)

proc get(ctx: JSContext; this: FormData; name: string): JSValue {.jsfunc.} =
  for entry in this.entries:
    if entry.name == name:
      if entry.isstr:
        return ctx.toJS(entry.svalue)
      else:
        return ctx.toJS(entry.value)
  return JS_NULL

proc getAll(ctx: JSContext; this: FormData; name: string): seq[JSValue]
    {.jsfunc.} =
  result = newSeq[JSValue]()
  for entry in this.entries:
    if entry.name == name:
      if entry.isstr:
        result.add(ctx.toJS(entry.svalue))
      else:
        result.add(ctx.toJS(entry.value))

proc add(list: var seq[FormDataEntry], entry: tuple[name, value: string]) =
  list.add(FormDataEntry(
    name: entry.name,
    isstr: true,
    svalue: entry.value
  ))

proc toNameValuePairs*(list: seq[FormDataEntry]):
    seq[tuple[name, value: string]] =
  result = @[]
  for entry in list:
    if entry.isstr:
      result.add((entry.name, entry.svalue))
    else:
      result.add((entry.name, entry.name))

const AutoDirInput = {
  itHidden, itText, itSearch, itTel, itURL, itEmail, itPassword, itSubmit,
  itReset, itButton
}

# https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#constructing-the-form-data-set
# Warning: we skip the first "constructing entry list" check; the caller must
# do it.
proc constructEntryList*(form: HTMLFormElement; submitter: Element = nil;
    encoding = "UTF-8"): seq[FormDataEntry] =
  assert not form.constructingEntryList
  form.constructingEntryList = true
  var entrylist: seq[FormDataEntry] = @[]
  for field in form.controls:
    if field.findAncestor(TAG_DATALIST) != nil or
        field.attrb(satDisabled) or
        field.isButton() and Element(field) != submitter:
      continue
    if field of HTMLInputElement:
      let field = HTMLInputElement(field)
      if field.inputType in {itCheckbox, itRadio} and not field.checked:
        continue
      if field.inputType == itImage:
        var name = field.attr(satName)
        if name != "":
          name &= '.'
        entrylist.add((name & 'x', $field.xcoord))
        entrylist.add((name & 'y', $field.ycoord))
        continue
    #TODO custom elements
    let name = field.attr(satName)
    if name == "":
      continue
    if field of HTMLSelectElement:
      let field = HTMLSelectElement(field)
      for option in field.options:
        if option.selected and not option.isDisabled:
          entrylist.add((name, option.value))
    elif field of HTMLInputElement:
      let field = HTMLInputElement(field)
      case field.inputType
      of itCheckbox, itRadio:
        let v = field.attr(satValue)
        let value = if v != "":
          v
        else:
          "on"
        entrylist.add((name, value))
      of itFile:
        for file in field.files:
          entrylist.add(FormDataEntry(
            name: name,
            filename: file.name,
            isstr: false,
            value: file
          ))
      of itHidden:
        if name.equalsIgnoreCase("_charset_"):
          entrylist.add((name, encoding))
        else:
          entrylist.add((name, field.value))
      else:
        entrylist.add((name, field.value))
    elif field of HTMLButtonElement:
      entrylist.add((name, HTMLButtonElement(field).attr(satValue)))
    elif field of HTMLTextAreaElement:
      entrylist.add((name, HTMLTextAreaElement(field).value))
    else:
      assert false, "Tag type " & $field.tagType &
        " not accounted for in constructEntryList"
    if field of HTMLTextAreaElement or
        field of HTMLInputElement and
        HTMLInputElement(field).inputType in AutoDirInput:
      let dirname = field.attr(satDirname)
      if dirname != "":
        let dir = "ltr" #TODO bidi
        entrylist.add((dirname, dir))
  form.constructingEntryList = false
  move(entrylist)

proc addFormDataModule*(ctx: JSContext) =
  ctx.registerType(FormData)

{.pop.} # raises: []
