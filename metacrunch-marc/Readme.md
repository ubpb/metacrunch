metacrunch-mab2
===============

[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch-mab2/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch-mab2)
[![Build Status](https://travis-ci.org/ubpb/metacrunch-mab2.svg)](https://travis-ci.org/ubpb/metacrunch-mab2)

This is the official MAB2 package for the [metacrunch ETL toolkit](https://github.com/ubpb/metacrunch). It allows you to parse MAB XML data and access the data by a simple and powerful API.

Note: There is no technical dependency to metacrunch, so it's fine to use this gem in any Ruby application where you need to access MAB XML data.


Installation
------------

```
$ gem install metacrunch-mab2
```


Usage example
-------------

For the full API look at the files in [https://github.com/ubpb/metacrunch-mab2/tree/master/lib/metacrunch/mab2](https://github.com/ubpb/metacrunch-mab2/tree/master/lib/metacrunch/mab2)

**Parsing a [MAB XML file](https://github.com/ubpb/metacrunch-mab2/blob/master/spec/assets/aleph_mab_xml/file1.xml)**
```ruby
document = Metacrunch::Mab2::Document.from_mab_xml(File.read("my/mab.xml"))
```

**Accessing control fields**
```ruby
document.controlfield("LDR")

# <Metacrunch::Mab2::Document::Controlfield:0x007f98061b4b08
# @tag="LDR",
# @values=["-", "-", "-", "-", "-", "-", "M", "2", ".", "0", "1", "2", "0", "0", "0", "2", "4", "-", "-", "-", "-", "-", "-", "h"]>
```

**Accessing data fields**
```ruby
document.datafields("100")

#<Metacrunch::Mab2::Document::DatafieldSet:0x007f98052e5af0
# @datafields=
#  [#<Metacrunch::Mab2::Document::Datafield:0x007f98061a5ea0
#    @ind1="-",
#    @ind2="1",
#    @subfields=
#     {"p"=>[#<Metacrunch::Mab2::Document::Subfield:0x007f98061a5dd8 @code="p", @value="Kofler, Michael">],
#      "d"=>[#<Metacrunch::Mab2::Document::Subfield:0x007f98061a5ce8 @code="d", @value="1967-">],
#      "9"=>[#<Metacrunch::Mab2::Document::Subfield:0x007f98061a5bf8 @code="9", @value="(DE-588)121636763">]},
#    @tag="100">]>
```

```ruby
document.datafields("100", ind1: :blank).subfields("p").value

# Kofler, Michael
```

License
-------

metacrunch-mab2 is available at [github](https://github.com/ubpb/metacrunch-mab2) under [MIT license](https://github.com/ubpb/metacrunch-mab2/blob/master/License.txt).
