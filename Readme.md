metacrunch
==========

[![Gem Version](https://badge.fury.io/rb/metacrunch.svg)](http://badge.fury.io/rb/metacrunch)
[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch)
[![Build Status](https://travis-ci.org/ubpb/metacrunch.svg)](https://travis-ci.org/ubpb/metacrunch)

metacrunch is a simple and lightweight data processing and ETL ([Extract-Load-Transform](http://en.wikipedia.org/wiki/Extract,_transform,_load))
toolkit for Ruby.


Installation
------------

```
$ gem install metacrunch
```


Create ETL jobs
---------------

The basic idea behind an ETL job in metacrunch is the concept of a data processing pipeline. Each ETL job reads data from one or more **sources**, runs one or more **transformations** on the data and finally writes the transformed data back to one or more **destinations**.

metacrunch provides you with a simple DSL to define such ETL jobs. Just create a text file with the extension `.metacrunch`. Note: The extension doesn't really matter but you should avoid `.rb` to not loading them by mistake from another Ruby component.

Let's look at an example.

```ruby
# File: my_etl_job.metacrunch

# Every metacrunch job file is a regular Ruby file. So you can always use regular Ruby
# stuff like defining a method
def my_helper
  # ...
end

# ... defining classes
class MyHelper
  # ...
end

# ... or loading other ruby files
require_relative "./some/other/ruby/file"

# Declare a source (use a build-in or 3rd party source or implement it – see notes below).
# At least one source is required to allow the job to run.
source MySource.new
# ... maybe another one. Sources are processed in the order they are defined.
source MyOtherSource.new

# Declare a destination (use a build-in or 3rd party destination or implement it – see notes below).
# Technically a destination is optional, but a job that doesn't store it's
# output doesn't really makes sense.
destination MyDestination.new
# ... you can have more destinations if you like
destination MyOtherDestination.new

# To process data use the #transformation hook.
transformation do |data|
  # Called for each data object that has been put in the pipeline by a source.

  # Do your data transformation process here.

  # You must return the data to keep it in the pipeline. Dismiss the
  # data conditionally by returning nil.
  data
end

# Instead of passing a block to #transformation you can pass a
# `callable` object (an object responding to #call).
transformation Proc.new {
  # Procs and Lambdas responds to #call
}

# MyTransformation defines #call
transformation MyTransformation.new

# To run arbitrary code before the first transformation use the #pre_process hook.
pre_process do
  # Called before the first transformation
end

# To run arbitrary code after the last transformation use the #post_process hook.
post_process do
  # Called after the last transformation
end

# Instead of passing a block to #pre_process or #post_process you can pass a
# `callable` object (an object responding to #call).
pre_process Proc.new {
  # Procs and Lambdas responds to #call
}

# MyCallable class defines #call
post_process MyCallable.new

```


Run ETL jobs
------------

metacrunch comes with a handy command line tool. In your terminal just call


```
$ metacrunch run my_etl_job.metacrunch
```

to run the job.


License
-------

metacrunch is available at [github](https://github.com/ubpb/metacrunch) under [MIT license](https://github.com/ubpb/metacrunch/blob/master/License.txt).
