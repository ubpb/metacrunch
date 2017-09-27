metacrunch-marcxml
==================

[![Build Status](https://travis-ci.org/ubpb/metacrunch-marcxml.svg)](https://travis-ci.org/ubpb/metacrunch-marcxml)
[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch-marcxml/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch-marcxml)

This is the official [MARCXML](http://www.loc.gov/standards/marcxml/) package for the [metacrunch ETL toolkit](https://github.com/ubpb/metacrunch). It allows you to access MARCXML data by a simple and powerful Ruby API.

There is no runtime dependency to metacrunch, so it's fine to use this gem in any Ruby application where you need to access MARCXML data.

*Note: Before 2.0 this package was incorrectly named `metacrunch-mab2` and has been renamed to `metacrunch-marcxml`. Due to this renaming and further development there are breaking API changes if you upgrade from 1.x to 2.x.*


Installation
------------

Include the gem in your `Gemfile`

```ruby
gem "metacrunch-marcxml", "~> 2.0.0"
```

and run `$ bundle install` to install it.

Or install it manually

```
$ gem install metacrunch-marcxml
```


Usage example
-------------

**Loading the library**
```ruby
require "metacrunch/marcxml"
```

**Parsing a [MARCXML file](http://d-nb.info/982392028/about/marcxml)**
```ruby
# Load a MARCXML file (from a remote location in this example).
require "open-uri"
marcxml = open("http://d-nb.info/982392028/about/marcxml"){|io| io.read}

# Now parse the file
document = Metacrunch::Marcxml.parse(marcxml)
# .. or use the convenience method
document = Metacrunch::Marcxml(marcxml)
```

**Accessing control fields**
```ruby
controlfield = document.controlfield("005")
# same as ...
controlfield = document.controlfield(5)
# => #<Metacrunch::Marcxml::Document::Controlfield:0x007fd4c5120ec0 ...>

tag = controlfield.tag
# => "005"
value = controlfield.value
# => "20130926112144.0"
```

**Accessing data fields / sub fields**
```ruby
# Find fields matching tag=100 and indicator1=1 (author)
datafield_set = document.datafields(100, ind1: "1")
# => #<Metacrunch::Marcxml::Document::DatafieldSet:0x007fd4c4ce4b40 ...>

first_author = datafield_set.first # set is an Enumerable
# => #<Metacrunch::Marcxml::Document::Datafield:0x007fd4c5129480 ...>

# Get the subfields matching code=a (author name)
subfield_set = first_author.subfields("a")
# => #<Metacrunch::Marcxml::Document::SubfieldSet:0x007fd4c4c779f0 ...>

# because sub field "a" is not repeatable we know there can only be one match
first_author_subfield = subfield_set.first # subfield_set is an Enumerable
# => #<Metacrunch::Marcxml::Document::Subfield:0x007fd4c5129660 ...>

first_author_name = first_author_subfield.value
# => "Orwell, George"

# ... there is a shortcut for this case
first_author_name = document.datafields(100, ind1: "1").subfields("a").first_value
```

License
-------

metacrunch-marcxml is available at [github](https://github.com/ubpb/metacrunch-marcxml) under [MIT license](https://github.com/ubpb/metacrunch-marcxml/blob/master/License.txt).
