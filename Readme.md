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


Creating ETL jobs
-----------------

The basic idea behind an ETL job in metacrunch is the concept of a data processing pipeline. Each ETL job reads data from one or more **sources** (extract step), runs one or more **transformations** (transform step) on the data and finally writes the transformed data to one or more **destinations** (load step).

metacrunch provides you with a simple DSL to define and run such ETL jobs. Just create a text file with the extension `.metacrunch`. *Note: The extension doesn't really matter but you should avoid `.rb` to not loading them by mistake from another Ruby component.*

Let's walk through the main steps of creating ETL jobs with metacrunch. For a collection of working examples check out our [metacrunch-demo](https://github.com/ubpb/metacrunch-demo) repo.

#### It's Ruby

Every `.metacrunch` job file is a regular Ruby file. So you can always use regular stuff like e.g. declaring methods, classes, variable and requiring other Ruby files. 

```ruby
# File: my_etl_job.metacrunch

def my_helper
  # ...
end

class MyHelper
  # ...
end

helper = MyHelper.new

require "SomeGem"
require_relative "./some/other/ruby/file"
```

#### Defining sources

A source (aka. a reader) is an object that reads data into the metacrunch processing pipeline. Use one of the build-in or 3rd party sources or implement it by yourself. Implementing sources is easy – [see notes below](#implementing-sources). You can declare one or more sources. They are processed in the order they are defined.

You must declare at least one source to allow a job to run.

```ruby
# File: my_etl_job.metacrunch

source Metacrunch::Fs::Reader.new(args)
source MySource.new
```

This example uses a build-in file reader source. To learn more about the build-in sources see [notes below](#built-in-sources-and-destinations).

#### Defining transformations

To process, transform or manipulate data use the `#transformation` hook. A transformation can be implemented as a block, a lambda or as an object. To learn more about transformations check the section about [implementing transformations](#implementing-transformations) below.

The current data object (the object that is currently read by the source) will be passed to the first transformation as a parameter. The return value of a transformation will then be passed to the next transformation - or to the destination if the current transformation is the last one.

If you return nil the current data object will be dismissed and the next transformation (or destination) won't be called.

```ruby
# File: my_etl_job.metacrunch

transformation do |data|
  # Called for each data object that has been read by a source.

  # Do your data transformation process here.

  # You must return the data to keep it in the pipeline. Dismiss the
  # data conditionally by returning nil.
  data
end

# Instead of passing a block to #transformation you can pass a
# `callable` object (any object responding to #call).
transformation ->(data) {
  # Lambdas responds to #call
}

# MyTransformation defines #call
transformation MyTransformation.new
```

#### Defining destinations

A destination (aka. a writer) is an object that writes the transformed data to an external system. Use one of the build-in or 3rd party destinations or implement it by yourself. Implementing destinations is easy – [see notes below](#implementing-destinations). You can declare one or more destinations. They are processed in the order they are defined.

```ruby
# File: my_etl_job.metacrunch

destination MyDestination.new
```

#### Pre/Post process 

To run arbitrary code before the first transformation use the 
`#pre_process` hook. To run arbitrary after the last transformation use the 
`#post_process`. Like transformations, `#post_process` and `#pre_process` can be called with a block, a lambda or a (callable) object.

```ruby
pre_process do
  # Called before the first transformation
end

post_process do
  # Called after the last transformation
end

pre_process ->() {
  # Lambdas responds to #call
}

# MyCallable class defines #call
post_process MyCallable.new
```

#### Defining options

TBD.

Running ETL jobs
----------------

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


Built in sources and destinations
---------------------------------

TBD.

Defining job dependencies
-------------------------

TBD.

Defining job options
--------------------

TBD.

License
-------

metacrunch is available at [github](https://github.com/ubpb/metacrunch) under [MIT license](https://github.com/ubpb/metacrunch/blob/master/License.txt).
