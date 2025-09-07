[first]: https://example.org

test [hello][hi world] test [first]a[second] [oops not found]

[hi world]: a
[second]:

test

[what]: <https://wrong.example> 'title' wrong, because the line has more text

[what]

[another]: <https://wrong.example>
'title' not parsed

[this one's right, but has no title][another]

[but incredibly, this is correct]:
<my url>
'but incredibly, this is correct'
[but incredibly, this is correct]

[Test][] asdf

[tesT]: hi

![test][png]

[png]: test.png
