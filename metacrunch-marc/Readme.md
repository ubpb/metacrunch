metacrunch-marcxml
==================

[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch-marcxml/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch-marcxml)
[![Build Status](https://travis-ci.org/ubpb/metacrunch-marcxml.svg)](https://travis-ci.org/ubpb/metacrunch-marcxml)

This is the official MARCXML package for the [metacrunch ETL toolkit](https://github.com/ubpb/metacrunch). It allows you to access [MARCXML](http://www.loc.gov/standards/marcxml/) data by a simple and powerful API.

*Note: There is no runtime dependency to metacrunch, so it's fine to use this gem in any Ruby application where you need to access MARCXML data.*


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
marcxml = open("http://d-nb.info/982392028/about/marcxml"){|io| io.read}
document = Metacrunch::Marcxml::Document.from_marcxml(marcxml)
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
