metacrunch-marcxml
==================

[![Gem Version](https://badge.fury.io/rb/metacrunch-marcxml.svg)](http://badge.fury.io/rb/metacrunch-marcxml)
[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch-marcxml/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch-marcxml)
[![Test Coverage](https://codeclimate.com/github/ubpb/metacrunch-marcxml/badges/coverage.svg)](https://codeclimate.com/github/ubpb/metacrunch-marcxml/coverage)
[![CircleCI](https://circleci.com/gh/ubpb/metacrunch-marcxml.svg?style=svg)](https://circleci.com/gh/ubpb/metacrunch-marcxml)

This is the official [MARCXML](http://www.loc.gov/standards/marcxml/) package for the [metacrunch ETL toolkit](https://github.com/ubpb/metacrunch). It allows you to access MARCXML data by a simple and powerful Ruby API.

There is no runtime dependency to metacrunch, so it's fine to use this gem in any Ruby application where you need to access MARCXML data.

*Note: Before 2.0 this package was named `metacrunch-mab2` and has been renamed to `metacrunch-marcxml`. Due to this renaming and further development there are breaking API changes if you upgrade from 1.x to 2.x.*


Installation
------------

Include the gem in your `Gemfile`

```ruby
gem "metacrunch-marcxml", "~> 4.0.0"
```

and run `$ bundle install` to install it.

Or install it manually

```
$ gem install metacrunch-marcxml
```


Usage example
-------------

*Note: For working examples on how to use this package in a metacrunch job check out our [demo repository](https://github.com/ubpb/metacrunch-demo).*

#### Loading the library

```ruby
require "metacrunch/marcxml"
```

#### Parsing a [MARCXML file](http://d-nb.info/982392028/about/marcxml)

```ruby
# Load a MARCXML file (from a remote location in this example).
require "open-uri"
marcxml = URI.open("http://d-nb.info/982392028/about/marcxml"){|io| io.read}

# Now parse the file
record = Metacrunch::Marcxml.parse(marcxml)
# .. or 
record = Metacrunch::Marcxml[marcxml]
# .. or
record = Metacrunch::Marcxml(marcxml)
```
If the MARCXML contains a collection of records you can set `collecton_mode: true` to get an array of all records. If set to false (the default) you get the first record.

```ruby
# Parse a record collection
marcxml = %{
    <collection>
        <record>...</record>
        <record>...</record>
        <record>...</record>
    </collection>
}
records      = Metacrunch::Marcxml.parse(marcxml, collection_mode: true)
first_record = Metacrunch::Marcxml.parse(marcxml, collection_mode: false)
```

#### Reading the leader

```ruby
leader = record.leader
# => #<Metacrunch::Marcxml::Record::Leader:0x00007f93741ddc10 ...>

leader.value
# => "00000pam a2200000 c 4500"
```

#### Reading control fields

```ruby
controlfield = record.controlfield("005")
# => #<Metacrunch::Marcxml::Document::Controlfield:0x007fd4c5120ec0 ...>

tag = controlfield.tag
# => "005"

value = controlfield.value
# => "20130926112144.0"
```

#### Reading data fields / sub fields

```ruby
# Find fields matching tag=100 and ind1=1 (author)
datafield_set = record.datafields("100", ind1: "1")
# => #<Metacrunch::Marcxml::Document::DatafieldSet:0x007fd4c4ce4b40 ...>

first_author = datafield_set.first # set is an Enumerable
# => #<Metacrunch::Marcxml::Document::Datafield:0x007fd4c5129480 ...>

# Get the sub fields matching code=a (author name)
subfield_set = first_author.subfields("a")
# => #<Metacrunch::Marcxml::Document::SubfieldSet:0x007fd4c4c779f0 ...>

# because sub field "a" is not repeatable we know there can only be one match
first_author_subfield = subfield_set.first # subfield_set is an Enumerable
# => #<Metacrunch::Marcxml::Document::Subfield:0x007fd4c5129660 ...>

first_author_name = first_author_subfield.value
# => "Orwell, George"

# ... this can be a one liner
first_author_name = record.datafields(100, ind1: "1").subfields("a").values.first
```

#### Direct value access using a query string

*FEATURE IS EXPERIMENTAL AND SUBJECT TO CHANGE*

Access fields as described above is flexible but very verbose. Most of the time you know your data and you are interested in a simple and direct way to access the field values.

For this case we provide a way to query field values using a simple query string.

```ruby
# Get the value of control field "005"
record["005"]
# => "20130926112144.0"

# Get the first value of data field tag=100, ind1=1, sub field code=a
record["1001*a"].first
# => "Orwell, George"
```

The query string syntax is simple. Each query string starts with three letters for the tag. If the tag starts with `00` it is considered a query for a control field value. Otherwise it is considered a data field / sub field query. In that case the next two characters are used to match ind1 and ind2. The default value is `*` which matches every indicator value. `#`, `-` and `_` are interpreted as `blank`. The last characters are used to match the code of the sub fields. To query for more than one sub field code you may separate them using commas.

By default sub field values are flattened. To get an array of matching sub field values for each matching data field set `flatten_subfields: false`.

By default only the values are returned. That means you can't see from which sub field the value was extracted. If you query for just one sub field this information is not needed. But if you query for more than one sub field it may be useful. To get the sub field value and the sub field code to can set `values_as_hash: true`. This works for control fields as well.

**Examples**

```ruby
record["1001#a"] 
# => [["Orwell, George"]]

record["1001#a", flatten_subfields: true] 
# => ["Orwell, George"]

record["020**a,c"]
# => [
#      ["9783548267456", "kart. : EUR 6.00 (DE), EUR 6.20 (AT), sfr 11.00"],
#      ["3548267459", "kart. : EUR 6.00 (DE), EUR 6.20 (AT), sfr 11.00"]
#    ]

record["264#1a,b,c", flatten_subfields: true]
# => ["Berlin", "Ullstein", "2007"]

record["264#1a,b,c", flatten_subfields: true, values_as_hash: true]
# => [{"a"=>"Berlin"}, {"b"=>"Ullstein"}, {"c"=>"2007"}]
```

License
-------

metacrunch-marcxml is available at [github](https://github.com/ubpb/metacrunch-marcxml) under [MIT license](https://github.com/ubpb/metacrunch-marcxml/blob/master/License.txt).
