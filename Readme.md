metacrunch
==========

[![Gem Version](https://badge.fury.io/rb/metacrunch.svg)](http://badge.fury.io/rb/metacrunch)
[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch)
[![Build Status](https://travis-ci.org/ubpb/metacrunch.svg)](https://travis-ci.org/ubpb/metacrunch)

metacrunch is a simple and lightweight data processing and ETL ([Extract-Transform-Load](http://en.wikipedia.org/wiki/Extract,_transform,_load))
toolkit for Ruby.


Installation
------------

```
$ gem install metacrunch
```


Create ETL jobs
---------------

The basic idea behind an ETL job in metacrunch is the concept of a data processing pipeline. Each ETL job reads data from one or more **sources** (extract step), runs one or more **transformations** (transform step) on the data and finally writes the transformed data back to one or more **destinations** (load step).

metacrunch provides you with a simple DSL to define such ETL jobs. Just create a text file with the extension `.metacrunch`. Note: The extension doesn't really matter but you should avoid `.rb` to not loading them by mistake from another Ruby component.

Let's take a look at an full featured example. For a collection of working examples check out our [metacrunch-demo](https://github.com/ubpb/metacrunch-demo) repo.

```ruby
# File: my_etl_job.metacrunch

# Every metacrunch job file is a regular Ruby file. So you can always use regular Ruby
# stuff like declaring methods
def my_helper
  # ...
end

# ... declaring classes
class MyHelper
  # ...
end

# ... declaring variables
foo = "bar"

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

metacrunch comes with a handy command line tool. In a terminal use


```
$ metacrunch run my_etl_job.metacrunch
```

to run a job.

If you use [Bundler](http://bundler.io) to manage dependencies for your jobs make sure to change into the directory where your Gemfile is (or set BUNDLE_GEMFILE environment variable) and run metacrunch with `bundle exec`.

```
$ bundle exec metacrunch run my_etl_job.metacrunch
```

Depending on your environment `bundle exec` may not be required (e.g. you have rubygems-bundler installed) but we recommend using it whenever you have a Gemfile you like to use. When using Bundler make sure to add `gem "metacrunch"` to the Gemfile.

To pass options to the job, separate job options from the metacrunch command options using the `@@` separator.

Use the following syntax

```
$ [bundle exec] metacrunch run [COMMAND_OPTIONS] JOB_FILE [@@ [JOB_OPTIONS] [JOB_ARGS...]]
```


Implementing sources
--------------------

A source (aka a reader) is any Ruby object that responds to the `each` method that yields data objects one by one. 

The data is usually a `Hash` instance, but could be other structures as long as the rest of your pipeline is expecting it.

Any `enumerable` object (e.g. `Array`) responds to `each` and can be used as a source in metacrunch. 

```ruby
# File: my_etl_job.metacrunch
source [1,2,3,4,5,6,7,8,9]
```

Usually you implement your sources as classes. Doing so you can unit test and reuse them. 

Here is a simple CSV source

```ruby
# File: my_csv_source.rb
require 'csv'

class MyCsvSource
  def initialize(input_file)
    @csv = CSV.open(input_file, headers: true, header_converters: :symbol)
  end

  def each
    @csv.each do |data|
      yield(data.to_hash)
    end
    @csv.close
  end
end
```

You can then use that source in your job

```ruby
# File: my_etl_job.metacrunch
require "my_csv_source"

source MyCsvSource.new("my_data.csv")
```


Implementing transformations
----------------------------

Transformations can be implemented as blocks or as a `callable`. A `callable` in Ruby is any object that responds to the `call` method. 

### Transformations as a block

When using the block syntax the current data row will be passed as a parameter.

```ruby
# File: my_etl_job.metacrunch

transformation do |data|
  # DO YOUR TRANSFORMATION HERE
  data = ...

  # Make sure to return the data to keep it in the pipeline. Dismiss the
  # data conditionally by returning nil.
  data
end

```

### Transformations as a callable

Procs and Lambdas in Ruby respond to `call`. They can be used to implement transformations similar to blocks.

```ruby
# File: my_etl_job.metacrunch

transformation -> (data) do
  # ...
end

```

Like sources you can create classes to test and reuse transformation logic. 

```ruby
# File: my_transformation.rb

class MyTransformation

  def call(data)
    # ...
  end

end
```

You can use this transformation in your job 

```ruby
# File: my_etl_job.metacrunch

require "my_transformation"

transformation MyTransformation.new

```

Implementing destinations
-------------------------

A destination (aka a writer) is any Ruby object that responds to `write(data)` and `close`.

Like sources you are encouraged to implement destinations as classes.

```ruby
# File: my_destination.rb

class MyDestination
  
  def write(data)
    # Write data to files, remote services, databases etc.
  end

  def close
    # Use this method to close connections, files etc.
  end

end
```

In your job

```ruby
# File: my_etl_job.metacrunch

require "my_destination"

destination MyDestination.new

```


Defining job dependencies
-------------------------

TBD.

Defining job options
--------------------

TBD.

License
-------

metacrunch is available at [github](https://github.com/ubpb/metacrunch) under [MIT license](https://github.com/ubpb/metacrunch/blob/master/License.txt).
