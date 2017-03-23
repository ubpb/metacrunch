metacrunch-marcxml
==================

**THIS IS THE CURRENT DEVELOPMENT VERSION. USE THE [LATEST 1.X RELEASE](https://github.com/ubpb/metacrunch-marcxml/releases/latest) FOR A STABLE VERSION.**

[![Build Status](https://travis-ci.org/ubpb/metacrunch-marcxml.svg)](https://travis-ci.org/ubpb/metacrunch-marcxml)
[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch-marcxml/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch-marcxml)
[![Test Coverage](https://codeclimate.com/github/ubpb/metacrunch-marcxml/badges/coverage.svg)](https://codeclimate.com/github/ubpb/metacrunch-marcxml/coverage)

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
document = Metacrunch::Marcxml::Document.parse(marcxml)
# .. or use the convenience method
document = Metacrunch::Marcxml::Document(marcxml)
```

**Accessing control fields**
```ruby
# TODO
```

**Accessing data fields**
```ruby
# TODO
```

```ruby
# TODO
```

License
-------

metacrunch-marcxml is available at [github](https://github.com/ubpb/metacrunch-marcxml) under [MIT license](https://github.com/ubpb/metacrunch-marcxml/blob/master/License.txt).
