# Form-related DOM interfaces.

{.push raises: [].}

import chame/tags
import html/catom
import html/dom
import html/domexception
import js/fromjs
import js/jsbind
import js/jsnull
import js/jsopaque
import js/jspropenumlist
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import types/blob
import types/formdata
import js/jsopt
import types/opt
import types/refstring
import types/url
import utils/twtstr

type
  FormMethod* = enum
    fmGet = "get"
    fmPost = "post"
    fmDialog = "dialog"

  FormEncodingType* = enum
    fetUrlencoded = "application/x-www-form-urlencoded",
    fetMultipart = "multipart/form-data",
    fetTextPlain = "text/plain"

  InputType* = enum
    itText = "text"
    itButton = "button"
    itCheckbox = "checkbox"
    itColor = "color"
    itDate = "date"
    itDatetimeLocal = "datetime-local"
    itEmail = "email"
    itFile = "file"
    itHidden = "hidden"
    itImage = "image"
    itMonth = "month"
    itNumber = "number"
    itPassword = "password"
    itRadio = "radio"
    itRange = "range"
    itReset = "reset"
    itSearch = "search"
    itSubmit = "submit"
    itTel = "tel"
    itTime = "time"
    itURL = "url"
    itWeek = "week"

  ButtonType* = enum
    btSubmit = "submit"
    btReset = "reset"
    btButton = "button"

type
  HTMLFormControlsCollectionObj {.pure, final.} = object of HTMLCollectionObj

  HTMLFormControlsCollection = JSRef[HTMLFormControlsCollectionObj]

  HTMLOptionsCollectionObj {.pure, final.} = object of HTMLCollectionObj

  HTMLOptionsCollection = JSRef[HTMLOptionsCollectionObj]

  RadioNodeListObj {.pure, final.} = object of NodeListObj
    parent: HTMLFormControlsCollection

  RadioNodeList = JSRef[RadioNodeListObj]

  HTMLFormElement* = JSRef[HTMLFormElementObj]

  HTMLFormElementObj {.pure, final.} = object of HTMLElementObj
    constructingEntryList*: bool
    firing*: bool
    controlsHead: FormAssociatedElement
    controlsTail: FormAssociatedElement
    relList: DOMTokenArray

  FormAssociatedElement* = JSRef[FormAssociatedElementObj]

  FormAssociatedElementObj* {.pure.} = object of HTMLElementObj
    form*: HTMLFormElement
    prev: FormAssociatedElement # previous control in form
    next: FormAssociatedElement # next control in form
    parserInserted*: bool

  HTMLButtonElement* = JSRef[HTMLButtonElementObj]

  HTMLButtonElementObj {.pure, final.} = object of FormAssociatedElementObj
    buttonType*: ButtonType

  HTMLSelectElement* = JSRef[HTMLSelectElementObj]

  HTMLSelectElementObj {.pure, final.} = object of FormAssociatedElementObj
    userValidity: bool

  HTMLOptionElement* = JSRef[HTMLOptionElementObj]

  HTMLOptionElementNil = JSNullRef[HTMLOptionElementObj]

  HTMLOptionElementObj {.pure, final.} = object of HTMLElementObj
    selected*: bool
    dirty: bool

  HTMLInputElement* = JSRef[HTMLInputElementObj]

  HTMLInputElementObj {.pure, final.} = object of FormAssociatedElementObj
    inputType*: InputType
    internalValue: RefString
    internalChecked: bool
    internalFiles: FileList # may be nil
    xcoord*: int
    ycoord*: int

  HTMLTextAreaElement* = JSRef[HTMLTextAreaElementObj]

  HTMLTextAreaElementObj {.pure, final.} = object of FormAssociatedElementObj
    dirty: bool
    internalValue: string

  HTMLOutputElement = JSRef[HTMLOutputElementObj]

  HTMLOutputElementObj {.pure, final.} = object of FormAssociatedElementObj
    dirty: bool
    internalValue: string

  HTMLLabelElement* = JSRef[HTMLLabelElementObj]

  HTMLLabelElementObj {.pure, final.} = object of HTMLElementObj

  HTMLAreaElement = JSRef[HTMLAreaElementObj]

  HTMLAreaElementObj {.pure, final.} = object of HTMLElementObj
    relList: DOMTokenArray

# Forward declarations
proc resetFormOwner(element: FormAssociatedElement)

proc files*(this: HTMLInputElement): FileList
proc checked*(input: HTMLInputElement): bool
proc setChecked*(input: HTMLInputElement; b: bool)
proc value*(this: HTMLInputElement): lent string
proc setValue*(this: HTMLInputElement; value: sink string)
proc selectedIndex*(this: HTMLSelectElement): int
proc setSelectedness(select: HTMLSelectElement)
proc defaultValue(this: HTMLOutputElement): string
proc value*(option: HTMLOptionElement): string
proc value*(this: HTMLTextAreaElement): string

proc getClassID(t: typedesc[HTMLAreaElement]): JSClassID
proc getClassID(t: typedesc[HTMLOutputElement]): JSClassID
proc getClassID(t: typedesc[HTMLTextAreaElement]): JSClassID
proc getClassID(t: typedesc[RadioNodeList]): JSClassID
proc getClassID*(t: typedesc[FormAssociatedElement]): JSClassID
proc getClassID*(t: typedesc[HTMLButtonElement]): JSClassID
proc getClassID*(t: typedesc[HTMLFormElement]): JSClassID
proc getClassID*(t: typedesc[HTMLInputElement]): JSClassID
proc getClassID*(t: typedesc[HTMLOptionElement]): JSClassID
proc getClassID*(t: typedesc[HTMLSelectElement]): JSClassID

iterator controls(form: HTMLFormElement): FormAssociatedElement {.inline.} =
  var control = form.controlsHead
  while control != nil:
    yield control
    control = control.next

iterator inputs(form: HTMLFormElement): HTMLInputElement {.inline.} =
  for control in form.controls:
    let control = control as HTMLInputElement
    if control != nil:
      yield control

iterator radiogroup(input: HTMLInputElement): HTMLInputElement {.inline.} =
  let name = input.asElement.name
  if name != CAtomNull and name != satUempty:
    if input.form != nil:
      for input in input.form.inputs:
        if input.asElement.name == name and input.inputType == itRadio:
          yield input
    else:
      let document = input.asNode.document
      for input in document.asParentNode.elementDescendants(ttInput):
        let input = input as HTMLInputElement
        if input.form == nil and input.asElement.name == name and
            input.inputType == itRadio:
          yield input

iterator options*(select: HTMLSelectElement): HTMLOptionElement {.inline.} =
  for child in select.asParentNode.elementList:
    if (let child = child as HTMLOptionElement; child != nil):
      yield child
    elif child.tagType == ttOptgroup:
      for opt in child.asParentNode.elementList:
        if (let opt = opt as HTMLOptionElement; opt != nil):
          yield opt

# Element extensions
proc hasInsertionStepsForm(element: Element): bool {.exportc: "cha_$1".} =
  element.tagType == ttOption or element of FormAssociatedElement

proc insertionStepsForm(element: Element) {.exportc: "cha_$1".} =
  case element.tagType
  of ttOption:
    let parent = element.asNode.parentElement
    if parent != nil:
      var select = parent as HTMLSelectElement
      if select == nil and parent.tagType == ttOptgroup:
        select = parent.asNode.parentElement as HTMLSelectElement
      if select != nil:
        select.setSelectedness()
  elif (let element = element as FormAssociatedElement; element != nil):
    if not element.parserInserted:
      element.resetFormOwner()

proc removingStepsForm(element: Element) {.exportc: "cha_$1".} =
  if (let element = element as FormAssociatedElement; element != nil):
    element.resetFormOwner()

proc cloningStepsForm(old, clone: Element) {.exportc: "cha_$1".} =
  if (let clone = clone as HTMLInputElement; clone != nil):
    let old = old as HTMLInputElement
    clone.inputType = old.inputType
    clone.setValue(old.value)
    #TODO dirty value flag
    clone.setChecked(old.checked)
    #TODO dirty checkedness flag

proc reflectAttributeForm(element: Element; name: StaticAtom; has: bool;
    value: string) {.exportc: "cha_$1".} =
  case element.tagType
  of ttInput:
    let input = element as HTMLInputElement
    case name
    of satValue: input.setValue(value)
    of satChecked: input.setChecked(has)
    of satType:
      input.inputType = parseEnumNoCase[InputType](value).get(itText)
    else: discard
  of ttOption:
    let option = element as HTMLOptionElement
    if name == satSelected:
      option.selected = has
  of ttButton:
    let button = element as HTMLButtonElement
    if name == satType:
      button.buttonType = parseEnumNoCase[ButtonType](value).get(btSubmit)
  of ttArea:
    let area = element as HTMLAreaElement
    if name == satRel:
      area.asElement.reflectTokens(area.relList, satRel, value)
  else: discard

proc getElementForm(element: Element): HTMLElement {.exportc: "cha_$1".} =
  let element = element as FormAssociatedElement
  if element != nil:
    return element.form.asHTMLElement
  HTMLElement(nil)

proc parseFormMethod(s: string): FormMethod =
  return parseEnumNoCase[FormMethod](s).get(fmGet)

proc getFormMethodAttr(element: Element; name: StaticAtom): string
    {.exportc: "cha_$1".} =
  let s = element.attr(name)
  if name == satFormmethod and s == "":
    return ""
  return $parseFormMethod(s)

proc isSubmitButton*(element: Element): bool =
  if (let element = element as HTMLButtonElement; element != nil):
    return element.buttonType == btSubmit
  elif (let element = element as HTMLInputElement; element != nil):
    return element.inputType in {itSubmit, itImage}
  return false

proc isButton*(element: Element): bool =
  if element.tagType == ttButton:
    return true
  if (let element = element as HTMLInputElement; element != nil):
    return element.inputType in {itSubmit, itButton, itReset, itImage}
  return false

proc getFormAction*(element: Element): string =
  if element.isSubmitButton():
    if element.attrb(satFormaction):
      return element.attr(satFormaction)
  if (let element = element as FormAssociatedElement; element != nil):
    let form = element.form.asElement
    if form != nil:
      if form.attrb(satAction):
        return form.attr(satAction)
  if element.tagType == ttForm:
    return element.attr(satAction)
  return ""

proc getFormEnctype*(element: Element): FormEncodingType =
  if element.tagType == ttForm:
    # Note: see below, this is not in the standard.
    if element.attrb(satEnctype):
      let s = element.attr(satEnctype)
      return parseEnumNoCase[FormEncodingType](s).get(fetUrlencoded)
  if element.isSubmitButton():
    if element.attrb(satFormenctype):
      let s = element.attr(satFormenctype)
      return parseEnumNoCase[FormEncodingType](s).get(fetUrlencoded)
  if (let element = element as FormAssociatedElement; element != nil):
    if (let form = element.form.asElement; form != nil):
      if form.attrb(satEnctype):
        let s = form.attr(satEnctype)
        return parseEnumNoCase[FormEncodingType](s).get(fetUrlencoded)
  return fetUrlencoded

proc getFormMethod*(element: Element): FormMethod =
  if element.tagType == ttForm:
    # The standard says nothing about this, but this code path is reached
    # on implicit form submission and other browsers seem to agree on this
    # behavior.
    return parseFormMethod(element.attr(satMethod))
  if element.isSubmitButton():
    if element.attrb(satFormmethod):
      return parseFormMethod(element.attr(satFormmethod))
  if (let element = element as FormAssociatedElement; element != nil):
    if (let form = element.form.asElement; form != nil):
      if form.attrb(satMethod):
        return parseFormMethod(form.attr(satMethod))
  return fmGet

proc resetElement*(element: Element; ctx: JSContext) =
  case element.tagType
  of ttInput:
    let input = element as HTMLInputElement
    case input.inputType
    of itCheckbox, itRadio:
      input.setChecked(input.asElement.attrb(satChecked))
    of itFile:
      if input.internalFiles != nil:
        input.internalFiles.clear()
    else:
      input.setValue(input.asElement.attr(satValue))
    input.asElement.invalidate()
  of ttSelect:
    let select = element as HTMLSelectElement
    select.userValidity = false
    for option in select.options:
      if option.asElement.attrb(satSelected):
        option.selected = true
      else:
        option.selected = false
      option.dirty = false
      option.asElement.invalidate(dtChecked)
    select.setSelectedness()
  of ttTextarea:
    let textarea = element as HTMLTextAreaElement
    textarea.dirty = false
    textarea.asElement.invalidate()
  of ttOutput:
    let output = element as HTMLOutputElement
    output.asParentNode.replaceAll(ctx, output.defaultValue.toDOMStringView())
    output.dirty = false
    output.internalValue = ""
  else: discard

proc isLabelable(element: Element): bool =
  #TODO custom elements
  const LabelableElements = {
    ttButton, ttMeter, ttOutput, ttProgress, ttSelect, ttTextarea
  }
  if element.tagType in LabelableElements:
    return true
  let element = element as HTMLInputElement
  return element != nil and element.inputType != itHidden

# HTMLFormControlsCollection
proc isRadioNode(this: Collection; node: Node): bool =
  let this = this as RadioNodeList
  if not this.parent[].match(this.parent.asCollection, node):
    return false
  let element = node as Element
  let name = this.atoms[0]
  element.id == name or
    element.namespaceURI == satNamespaceHTML and element.name == name

jsClassDef(HTMLFormControlsCollection):
  jsextends HTMLCollectionDef

  proc namedItem(ctx: JSContext; this: HTMLFormControlsCollection;
      name: CAtom): JSValue {.jsfunc.} =
    let nodes = jsNew RadioNodeListObj(
      match: isRadioNode,
      root: this.root,
      invalid: true,
      atoms: @[name],
      parent: this,
      mode: cmTree
    )
    if nodes != nil:
      nodes.asCollectionLike.attach()
      let len = nodes.asCollection.getLength()
      if len == 0:
        return JS_NULL
      if len == 1:
        return ctx.toJS(nodes.snapshot[0])
    return ctx.toJSNew(nodes)

  proc names(ctx: JSContext; this: HTMLFormControlsCollection):
      JSPropertyEnumList {.jspropnames.} =
    return ctx.names(this.asHTMLCollection)

  proc getter(ctx: JSContext; this: HTMLFormControlsCollection; atom: JSAtom):
      JSValue {.jsgetownprop.} =
    var u: uint32
    var s: CAtom
    case ctx.fromIdx(atom, u, s)
    of fiIdx: ctx.toJS(this.asHTMLCollection.item(u)).uninitIfNull()
    of fiStr: ctx.namedItem(this, s).uninitIfNull()
    of fiErr: JS_EXCEPTION

# RadioNodeList
jsClassDef(RadioNodeList):
  jsextends NodeListDef

# HTMLOptionsCollection
proc isOptionOf(node, select: Node): bool =
  if node of HTMLOptionElement:
    let parent = node.parentElement
    return parent.asNode == select or
      parent.tagType == ttOptgroup and parent.parentNode.asNode == select
  return false

proc isOptionOfRoot(this: Collection; node: Node): bool =
  node.isOptionOf(this.root)

jsClassDef(HTMLOptionsCollection):
  jsextends HTMLCollectionDef

  proc names(ctx: JSContext; this: HTMLOptionsCollection): JSPropertyEnumList
      {.jspropnames.} =
    return ctx.names(this.asHTMLCollection)

  proc getter(ctx: JSContext; this: HTMLOptionsCollection; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    return ctx.getter(this.asHTMLCollection, atom)

  proc add(ctx: JSContext; this: HTMLOptionsCollection; element: Element;
      before: JSValueConst = JS_NULL): JSValue {.jsfunc.} =
    if element.tagType notin {ttOption, ttOptgroup}:
      return JS_ThrowTypeError(ctx, "expected option or optgroup element")
    var beforeEl: HTMLElement
    var beforeIdx = -1
    if not JS_IsNull(before) and ctx.fromJS(before, beforeEl).isErr and
        ctx.fromJS(before, beforeIdx).isErr:
      return JS_EXCEPTION
    for it in this.root.ancestors:
      if element == it:
        return ctx.insertThrow("can't add ancestor of select")
    if beforeEl != nil and this.root notin beforeEl.asNode:
      return ctx.insertThrow(nil)
    if element != beforeEl:
      if beforeEl == nil:
        beforeEl = this.asHTMLCollection.item(uint32(beforeIdx)) as HTMLElement
      let parent = if beforeEl != nil:
        beforeEl.parentNode.asNode
      else:
        this.root
      return ctx.insertBeforeUndefined(parent, element.asNode,
        jsNull(beforeEl.asNode))
    return JS_UNDEFINED

  proc remove(ctx: JSContext; this: HTMLOptionsCollection; i: int32)
      {.jsfunc.} =
    let element = this.asHTMLCollection.item(uint32(i))
    if element != nil:
      element.asNode.removeImpl(ctx)

  proc length(this: HTMLOptionsCollection): uint32 {.jsfget.} =
    this.asCollection.getLength()

  proc setLength(ctx: JSContext; this: HTMLOptionsCollection; n: uint32)
      {.jsfset: "length".} =
    let len = this.length
    if n > len:
      if n <= 100_000: # LOL
        let parent = this.root as ParentNode
        let document = parent.asNode.document
        for i in 0 ..< n - len:
          let option = document.newHTMLElement(ttOption)
          if option == nil:
            break
          parent.append(ctx, option.asNode)
    else:
      for i in 0 ..< len - n:
        let it = this.asHTMLCollection.item(uint32(i))
        it.asNode.removeImpl(ctx)

  proc setter(ctx: JSContext; this: HTMLOptionsCollection; atom: JSAtom;
      value: HTMLOptionElementNil): JSValue {.jssetprop.} =
    var u: uint32
    case ctx.fromIdx(atom, u)
    of fiIdx: discard
    of fiStr: return JS_UNINITIALIZED
    of fiErr: return JS_EXCEPTION
    let element = this.asHTMLCollection.item(u)
    let value = value.get.asNode
    if value == nil:
      if element != nil:
        element.asNode.removeImpl(ctx)
      return JS_UNDEFINED
    let parent = this.root as ParentNode
    if element != nil:
      return ctx.replaceChildWithThrow(parent.asNode, element.asNode, value)
    let len = this.length
    let document = parent.asNode.document
    for i in len ..< u:
      let option = document.newHTMLElement(ttOption)
      if option == nil:
        return JS_ThrowOutOfMemory(ctx)
      parent.append(ctx, option.asNode)
    return ctx.insertBeforeUndefined(parent.asNode, value, jsNull(Node))

  proc selectedIndex(this: HTMLOptionsCollection): int {.jsfget.} =
    return (this.root as HTMLSelectElement).selectedIndex

# FormAssociatedElement
proc setForm*(element: FormAssociatedElement; form: HTMLFormElement) =
  element.form = form
  if form.controlsTail == nil:
    form.controlsHead = element
  else:
    form.controlsTail.next = element
  element.prev = form.controlsTail
  form.controlsTail = element
  form.asNode.document.invalidateCollections()

proc resetFormOwner(element: FormAssociatedElement) =
  element.parserInserted = false
  if element.form != nil:
    if element.asHTMLElement.tagType notin ListedElements:
      return
    let lastForm = element.asNode.findAncestor(ttForm)
    if not element.asElement.attrb(satForm) and lastForm == element.form:
      return
  let form = element.form
  if form != nil:
    if element.prev == nil:
      form.controlsHead = element.next
    else:
      element.prev.next = element.next
    if element.next == nil:
      form.controlsTail = element.prev
    else:
      element.next.prev = element.prev
    element.prev = FormAssociatedElement(nil)
    element.next = FormAssociatedElement(nil)
    element.form = HTMLFormElement(nil)
  if element.asHTMLElement.tagType in ListedElements and
      element.asNode.isConnected:
    let id = element.asElement.attr(satForm).toAtom()
    let form = element.asNode.document.asRootNode.getElementById(id) as
      HTMLFormElement
    if form != nil:
      element.setForm(form)
  if element.form == nil:
    for ancestor in element.asNode.ancestors:
      let ancestor = ancestor as HTMLFormElement
      if ancestor != nil:
        element.setForm(ancestor)

const AutoDirInput = {
  itHidden, itText, itSearch, itTel, itURL, itEmail, itPassword, itSubmit,
  itReset, itButton
}

jsClassPublicDef(FormAssociatedElement): # fake class
  jsextends HTMLElementDef

# <area>
jsClassDef(HTMLAreaElement):
  jsextends HTMLElementDef

  proc toString(this: HTMLAreaElement): string {.jsfunc.} =
    if href := this.asElement.reinitURL():
      return $href
    return ""

  proc getRelList(this: HTMLAreaElement): DOMTokenList {.jsfget: "relList".} =
    this.asElement.getDOMTokenList(this.relList, satRel)

  proc setRelList(ctx: JSContext; this: HTMLAreaElement; ds: DOMString) {.
      jsfset: "relList".} =
    this.asElement.setAttr(ctx, satRel, ds)

# <button>
jsClassPublicDef(HTMLButtonElement):
  jsextends FormAssociatedElementDef

  jsget HTMLButtonElement, buttonType, "type"

  proc setType(ctx: JSContext; this: HTMLButtonElement; s: DOMString) {.
      jsfset: "type".} =
    this.asElement.setAttr(ctx, satType, s)

# <form>
proc canSubmitImplicitly*(form: HTMLFormElement): bool =
  const BlocksImplicitSubmission = {
    itText, itSearch, itURL, itTel, itEmail, itPassword, itDate, itMonth,
    itWeek, itTime, itDatetimeLocal, itNumber
  }
  var found = false
  for control in form.controls:
    let input = control as HTMLInputElement
    if input != nil:
      if input.inputType in BlocksImplicitSubmission:
        if found:
          return false
        found = true
    elif control.asElement.isSubmitButton():
      return false
  return true

proc resetForm*(form: HTMLFormElement; ctx: JSContext) =
  for control in form.controls:
    control.asElement.resetElement(ctx)
    control.asElement.invalidate()

# https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#constructing-the-form-data-set
# Warning: we skip the first "constructing entry list" check; the caller must
# do it.
proc constructEntryList*(form: HTMLFormElement; submitter = HTMLElement(nil);
    encoding = "UTF-8"): seq[FormDataEntry] =
  assert not form.constructingEntryList
  form.constructingEntryList = true
  var entrylist: seq[FormDataEntry] = @[]
  for field in form.controls:
    if field.asNode.findAncestor(ttDatalist) != nil or
        field.asElement.attrb(satDisabled) or
        field.asElement.isButton() and submitter != field:
      continue
    if (let field = field as HTMLInputElement; field != nil):
      if field.inputType in {itCheckbox, itRadio} and not field.checked:
        continue
      if field.inputType == itImage:
        var name = field.asElement.attr(satName)
        if name != "":
          name &= '.'
        entrylist.add((name & 'x', $field.xcoord))
        entrylist.add((name & 'y', $field.ycoord))
        continue
    #TODO custom elements
    let name = field.asElement.attr(satName)
    if name == "":
      continue
    if (let field = field as HTMLSelectElement; field != nil):
      for option in field.options:
        if option.selected and not option.asElement.isDisabled:
          entrylist.add((name, option.value))
    elif (let field = field as HTMLInputElement; field != nil):
      case field.inputType
      of itCheckbox, itRadio:
        let v = field.asElement.attr(satValue)
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
            value: file.asBlob
          ))
      of itHidden:
        if name.equalsIgnoreCase("_charset_"):
          entrylist.add((name, encoding))
        else:
          entrylist.add((name, field.value))
      else:
        entrylist.add((name, field.value))
    elif (let field = field as HTMLButtonElement; field != nil):
      entrylist.add((name, field.asElement.attr(satValue)))
    elif (let field = field as HTMLTextAreaElement; field != nil):
      entrylist.add((name, field.value))
    else:
      assert false, $field.asHTMLElement.tagType
    let input = field as HTMLInputElement
    if field.asHTMLElement.tagType == ttTextarea or
        input != nil and input.inputType in AutoDirInput:
      let dirname = field.asElement.attr(satDirname)
      if dirname != "":
        let dir = "ltr" #TODO bidi
        entrylist.add((dirname, dir))
  form.constructingEntryList = false
  move(entrylist)

proc newFormDataImpl(ctx: JSContext; argv: varargs[JSValueConst]):
    Opt[FormData] {.exportc: "cha_$1".} =
  let urandom = ctx.getGlobal().urandom
  let this = newFormData0(urandom)
  if this != nil and argv.len > 0:
    var form: HTMLFormElement
    var submitter: HTMLElement
    ?ctx.fromJS(argv[0], form)
    if argv.len > 1:
      ?ctx.fromJS(argv[1], submitter)
      if not submitter.asElement.isSubmitButton():
        JS_ThrowDOMException(ctx, "InvalidStateError",
          "submitter must be a submit button")
        return err()
      if (submitter as FormAssociatedElement).form != form:
        JS_ThrowDOMException(ctx, "InvalidStateError",
          "submitter's form owner is not form")
        return err()
    if not form.constructingEntryList:
      this.entries = constructEntryList(form, submitter)
  ok(this)

proc isFormControl(this: Collection; node: Node): bool =
  let element = node as FormAssociatedElement
  if element != nil:
    if element.asHTMLElement.tagType in ListedElements:
      return element.form.asNode == this.root
  return false

jsClassPublicDef(HTMLFormElement):
  jsextends HTMLElementDef

  proc getRelList(this: HTMLFormElement): DOMTokenList {.jsfget: "relList".} =
    this.asElement.getDOMTokenList(this.relList, satRel)

  proc setRelList(ctx: JSContext; this: HTMLFormElement; s: DOMString) {.
      jsfset: "relList".} =
    this.asElement.setAttr(ctx, satRel, s)

  proc elements(this: HTMLFormElement): HTMLFormControlsCollection
      {.jsnfget.} =
    var collection = this.asNode.getLiveCollection(cnElements) as
      HTMLFormControlsCollection
    if collection == nil:
      collection = jsNew HTMLFormControlsCollectionObj(
        root: this.asNode,
        match: isFormControl,
        invalid: true,
        mode: cmTree
      )
      if collection != nil:
        collection.asCollectionLike.attach()
        collection.setMagic(uint32(cnElements))
    collection

  proc getter(ctx: JSContext; this: HTMLFormElement; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    let elements = this.elements()
    if elements == nil:
      return JS_ThrowOutOfMemory(ctx)
    return ctx.getter(elements, atom)

  proc length(this: HTMLFormElement): uint32 {.jsfget.} =
    let elements = this.elements()
    if elements == nil:
      return 0
    return elements.asCollection.getLength()

# <input>
proc setValue*(this: HTMLInputElement; value: sink string) =
  this.internalValue = newRefString(value)
  this.asElement.invalidate()

proc addFile*(this: HTMLInputElement; file: WebFile) =
  this.files.add(file)
  this.asElement.invalidate()

proc inputString*(input: HTMLInputElement): RefString =
  case input.inputType
  of itCheckbox, itRadio:
    if input.checked:
      return newRefString("*")
    return newRefString(" ")
  of itPassword:
    return newRefString('*'.repeat(input.value.pointLen))
  of itReset:
    if input.asElement.attrb(satValue):
      return input.internalValue
    return newRefString("RESET")
  of itSubmit, itButton:
    if input.asElement.attrb(satValue):
      return input.internalValue
    return newRefString("SUBMIT")
  of itFile:
    return newRefString(input.files.getName())
  else:
    return input.internalValue

jsClassPublicDef(HTMLInputElement):
  jsextends FormAssociatedElementDef

  jsget HTMLInputElement, inputType, "type"

  proc value*(this: HTMLInputElement): lent string {.jsfget.} =
    if this.internalValue == nil:
      this.internalValue = newRefString("")
    return this.internalValue.s

  proc setValue(this: HTMLInputElement; ds: DOMString) {.jsfset: "value".} =
    this.setValue($ds)

  proc setType(ctx: JSContext; this: HTMLInputElement; s: DOMString) {.
      jsfset: "type".} =
    this.asElement.setAttr(ctx, satType, s)

  proc checked*(input: HTMLInputElement): bool {.jsfget.} =
    return input.internalChecked

  proc setChecked*(input: HTMLInputElement; b: bool) {.jsfset: "checked".} =
    # Note: input elements are implemented as a replaced text, so we must
    # fully invalidate them on checked change.
    if input.inputType == itRadio and b:
      for radio in input.radiogroup:
        radio.asElement.invalidate(dtChecked)
        radio.asElement.invalidate()
        radio.internalChecked = false
    input.asElement.invalidate(dtChecked)
    input.asElement.invalidate()
    input.internalChecked = b

  proc files*(this: HTMLInputElement): FileList {.jsfget.} =
    if this.internalFiles == nil:
      this.internalFiles = newFileList()
    this.internalFiles

  proc select(ctx: JSContext; input: HTMLInputElement) {.jsfunc.} =
    input.asElement.focus()

# <label>
jsClassDef(HTMLLabelElement):
  jsextends HTMLElementDef

  proc control*(label: HTMLLabelElement): HTMLElement {.jsfget.} =
    let i = label.asElement.findAttr(satFor)
    if i >= 0:
      let id = label.asElement.getAttr(i).toAtom()
      let element = label.asNode.document.asRootNode.getElementById(id)
      if element != nil and element.isLabelable():
        return element as HTMLElement
      return HTMLElement(nil)
    for element in label.asParentNode.elementDescendants:
      if element.isLabelable():
        return element as HTMLElement
    return HTMLElement(nil)

  proc form(label: HTMLLabelElement): HTMLFormElement {.jsfget.} =
    let control = label.control as FormAssociatedElement
    if control != nil:
      return control.form
    return HTMLFormElement(nil)

# <option>
proc newOption(ctx: JSContext; _: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let document = ctx.getDocument()
  let this = document.newHTMLElement(ttOption) as HTMLOptionElement
  if argc >= 1 and not JS_IsUndefined(argv[0]):
    var text: DOMString
    ?ctx.fromJS(argv[0], text)
    if text.len > 0:
      let node = document.newText(text)
      if node == nil:
        return JS_ThrowOutOfMemory(ctx)
      this.asParentNode.append(ctx, node.asNode)
  if argc >= 2 and not JS_IsUndefined(argv[1]):
    var value: DOMString
    ?ctx.fromJS(argv[1], value)
    this.asElement.setAttr(ctx, satValue, value)
  if argc >= 3:
    var defaultSelected: bool
    ?ctx.fromJS(argv[2], defaultSelected)
    if defaultSelected:
      this.asElement.setAttr(ctx, satSelected, "")
  if argc >= 4:
    ?ctx.fromJS(argv[3], this.selected)
  ctx.toJS(this)

proc select*(option: HTMLOptionElement): HTMLSelectElement =
  for ancestor in option.asNode.ancestors:
    let select = ancestor as HTMLSelectElement
    if select != nil:
      return select
  return HTMLSelectElement(nil)

jsClassPublicDef(HTMLOptionElement):
  jsextends HTMLElementDef

  jsget HTMLOptionElement, selected

  proc text(option: HTMLOptionElement): string {.jsfget.} =
    var s = ""
    for child in option.asParentNode.descendants:
      let parent = child.parentElement
      let child = child as Text
      if child != nil and (parent.tagTypeNoNS != ttScript or
          parent.namespaceURI notin [satNamespaceHTML, satNamespaceSVG]):
        s &= child.data.s
    return s.stripAndCollapse()

  proc value*(option: HTMLOptionElement): string {.jsfget.} =
    if option.asElement.attrb(satValue):
      return option.asElement.attr(satValue)
    return option.text

  proc setValue(ctx: JSContext; option: HTMLOptionElement; ds: DOMString) {.
      jsfset: "value".} =
    option.asElement.setAttr(ctx, satValue, ds)

  proc setSelected*(option: HTMLOptionElement; selected: bool)
      {.jsfset: "selected".} =
    option.asElement.invalidate(dtChecked)
    option.selected = selected
    let select = option.select
    if select != nil and not select.asElement.attrb(satMultiple):
      var firstOption: HTMLOptionElement
      var prevSelected: HTMLOptionElement
      for option in select.options:
        if firstOption == nil:
          firstOption = option
        if option.selected:
          if prevSelected != nil:
            prevSelected.selected = false
            prevSelected.asElement.invalidate(dtChecked)
          prevSelected = option
      if select.asElement.attrul(satSize).get(1) == 1 and
          prevSelected == nil and firstOption != nil:
        firstOption.selected = true
        firstOption.asElement.invalidate(dtChecked)

# <output>
jsClassDef(HTMLOutputElement):
  jsextends FormAssociatedElementDef

  proc getType(this: HTMLOutputElement): string {.jsfget: "type".} =
    return "output"

  proc defaultValue(this: HTMLOutputElement): string {.jsfget.} =
    if this.dirty:
      return this.internalValue
    return this.asNode.textContent

  proc setDefaultValue(ctx: JSContext; this: HTMLOutputElement; ds: DOMString)
      {.jsfset: "defaultValue".} =
    if this.dirty:
      this.dirty = true
      this.internalValue = $ds
    else:
      this.asParentNode.replaceAll(ctx, ds)

  proc value(this: HTMLOutputElement): string {.jsfget.} =
    return this.asNode.textContent

  proc setValue(ctx: JSContext; this: HTMLOutputElement; ds: DOMString) {.
      jsfset: "value".} =
    if not this.dirty:
      this.dirty = true
      this.internalValue = this.asNode.textContent
    this.asParentNode.replaceAll(ctx, ds)

# <select>
proc displaySize(select: HTMLSelectElement): uint32 =
  return select.asElement.attrul(satSize).get(1)

proc setSelectedness(select: HTMLSelectElement) =
  var firstOption: HTMLOptionElement
  var prevSelected: HTMLOptionElement
  if not select.asElement.attrb(satMultiple):
    let displaySize = select.displaySize
    for option in select.options:
      if firstOption == nil:
        firstOption = option
      if option.selected:
        if prevSelected != nil:
          prevSelected.selected = false
          prevSelected.asElement.invalidate(dtChecked)
        prevSelected = option
    if select.displaySize == 1 and prevSelected == nil and firstOption != nil:
      firstOption.selected = true

proc isSelectedOptionOf(this: Collection; node: Node): bool =
  this.isOptionOfRoot(node) and (node as HTMLOptionElement).selected

jsClassPublicDef(HTMLSelectElement):
  jsextends FormAssociatedElementDef

  proc jsType(this: HTMLSelectElement): string {.jsfget: "type".} =
    if this.asElement.attrb(satMultiple):
      return "select-multiple"
    return "select-one"

  proc options(this: HTMLSelectElement): HTMLOptionsCollection {.jsnfget.} =
    var collection = this.asNode.getLiveCollection(cnOptions) as
      HTMLOptionsCollection
    if collection == nil:
      collection = jsNew HTMLOptionsCollectionObj(
        match: isOptionOfRoot,
        root: this.asNode,
        invalid: true
      )
      if collection != nil:
        collection.asCollectionLike.attach()
        collection.setMagic(uint32(cnOptions))
    collection

  proc length(ctx: JSContext; this: HTMLSelectElement): uint32 {.jsfget.} =
    let options = this.options()
    if options == nil:
      return 0
    options.asCollection.getLength()

  proc setLength(ctx: JSContext; this: HTMLSelectElement; n: uint32) {.
      jsfset: "length".} =
    let options = this.options()
    if options != nil:
      ctx.setLength(options, n)

  proc getter(ctx: JSContext; this: HTMLSelectElement; u: JSAtom): JSValue
      {.jsgetownprop.} =
    let options = this.options()
    if options == nil:
      return JS_ThrowOutOfMemory(ctx)
    return ctx.getter(options, u)

  proc item(this: HTMLSelectElement; u: uint32): Element {.jsnfunc.} =
    let options = this.options()
    if options != nil:
      options.asHTMLCollection.item(u)
    else:
      Element(nil)

  proc namedItem(ctx: JSContext; this: HTMLSelectElement; atom: CAtom):
      Element {.jsnfunc.} =
    let options = this.options()
    if options != nil:
      options.asHTMLCollection.namedItem(atom)
    else:
      Element(nil)

  proc selectedOptions(this: HTMLSelectElement): HTMLCollection {.jsnfget.} =
    this.asParentNode.getHTMLCollection(isSelectedOptionOf, cmSubtree,
      cnSelectedOptions)

  proc selectedIndex*(this: HTMLSelectElement): int {.jsfget.} =
    var i = 0
    for it in this.options:
      if it.selected:
        return i
      inc i
    return -1

  proc setSelectedIndex*(this: HTMLSelectElement; n: int)
      {.jsfset: "selectedIndex".} =
    var i = 0
    for it in this.options:
      if i == n:
        it.selected = true
        it.dirty = true
      else:
        it.selected = false
      it.asElement.invalidate(dtChecked)
      inc i
    this.asNode.document.invalidateCollections()

  proc value(this: HTMLSelectElement): string {.jsfget.} =
    for it in this.options:
      if it.selected:
        return it.value
    return ""

  proc setValue(this: HTMLSelectElement; value: DOMString) {.jsfset: "value".} =
    var found = false
    for it in this.options:
      if not found and it.value == value.toOpenArray():
        found = true
        it.selected = true
        it.dirty = true
      else:
        it.selected = false
      it.asElement.invalidate(dtChecked)
    this.asNode.document.invalidateCollections()

  proc showPicker(ctx: JSContext; this: HTMLSelectElement): JSValue
      {.jsfunc.} =
    # Per spec, we should do something if it's being rendered and on
    # transient user activation.
    # If this is ever implemented, then the "is rendered" check must
    # be app mode only.
    return JS_ThrowDOMException(ctx, "NotAllowedError", "not allowed")

  proc add(ctx: JSContext; this: HTMLSelectElement; element: Element;
      before: JSValueConst = JS_NULL): JSValue {.jsfunc.} =
    let options = this.options()
    if options == nil:
      return JS_ThrowOutOfMemory(ctx)
    return ctx.add(options, element, before)

  proc remove(ctx: JSContext; this: HTMLSelectElement;
      idx: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
    if idx.len > 0:
      var i: int32
      ?ctx.fromJS(idx[0], i)
      let options = this.options()
      ctx.remove(options, i)
    else:
      this.asNode.removeImpl(ctx)
    ok()

# <textarea>
proc setValue*(this: HTMLTextAreaElement; s: sink string) =
  this.dirty = true
  this.internalValue = s
  this.asElement.invalidate()

jsClassDef(HTMLTextAreaElement):
  jsextends FormAssociatedElementDef

  proc value*(this: HTMLTextAreaElement): string {.jsfget.} =
    if this.dirty:
      return this.internalValue
    return this.asParentNode.childTextContent

  proc setValue(this: HTMLTextAreaElement; ds: DOMString) {.jsfset: "value".} =
    this.setValue($ds)

  proc defaultValue(this: HTMLTextAreaElement): string {.jsfget.} =
    this.asParentNode.childTextContent

  proc setDefaultValue(ctx: JSContext; this: HTMLTextAreaElement; ds: DOMString)
      {.jsfset: "defaultValue".} =
    this.asParentNode.replaceAll(ctx, ds)

proc newHTMLElementForm(tagType: TagType): HTMLElement {.exportc: "cha_$1".} =
  case tagType
  of ttForm: return (jsNew HTMLFormElementObj()).asHTMLElement
  of ttInput: return (jsNew HTMLInputElementObj()).asHTMLElement
  of ttSelect: return (jsNew HTMLSelectElementObj()).asHTMLElement
  of ttOption: return (jsNew HTMLOptionElementObj()).asHTMLElement
  of ttButton: return (jsNew HTMLButtonElementObj()).asHTMLElement
  of ttTextarea: return (jsNew HTMLTextAreaElementObj()).asHTMLElement
  of ttOutput: return (jsNew HTMLOutputElementObj()).asHTMLElement
  of ttLabel: return (jsNew HTMLLabelElementObj()).asHTMLElement
  of ttArea: return (jsNew HTMLAreaElementObj()).asHTMLElement
  else: return HTMLElement(nil)

proc addFormModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(HTMLFormControlsCollectionDef)
  ?ctx.registerClass(RadioNodeListDef)
  ?ctx.registerClass(HTMLOptionsCollectionDef)
  ?ctx.registerFakeClass(FormAssociatedElementDef)
  ?ctx.registerClass(HTMLFormElementDef)
  ?ctx.registerClass(HTMLInputElementDef)
  ?ctx.registerClass(HTMLSelectElementDef)
  ?ctx.registerClass(HTMLOptionElementDef)
  ?ctx.registerClass(HTMLButtonElementDef)
  ?ctx.registerClass(HTMLTextAreaElementDef)
  ?ctx.registerClass(HTMLLabelElementDef)
  ?ctx.registerClass(HTMLOutputElementDef)
  ?ctx.registerClass(HTMLAreaElementDef)
  if ctx.getOpaque() != nil:
    ?ctx.addHyperlinkUtils(HTMLAreaElementDef.id)
    ?ctx.addConstructorAlias(newOption, HTMLOptionElementDef.id, "Option")
    ?ctx.reflectAttributes(HTMLFormElementDef.id, raName, raNovalidate,
      raMethod)
    ?ctx.reflectAttributes(HTMLInputElementDef.id, raRequired, raName,
      raSizeInput, raFormmethod, raSrc, raForm)
    ?ctx.reflectAttributes(HTMLSelectElementDef.id, raRequired, raName,
      raSizeSelect, raDisabled, raForm)
    ?ctx.reflectAttributes(HTMLOptionElementDef.id, raSelected, raDisabled)
    ?ctx.reflectAttributes(HTMLButtonElementDef.id, raValueStr, raFormmethod)
    ?ctx.reflectAttributes(HTMLTextAreaElementDef.id, raRequired, raName,
      raCols, raRows, raForm)
    ?ctx.reflectAttributes(HTMLLabelElementDef.id, raTarget, raRel, raFor)
    ?ctx.reflectAttributes(HTMLOutputElementDef.id, raName, raFor, raForm)
    ?ctx.reflectAttributes(HTMLAreaElementDef.id, raTarget)
  ok()

{.pop.} # raises: []
