metacrunch
==========

[![Gem Version](https://badge.fury.io/rb/metacrunch.svg)](http://badge.fury.io/rb/metacrunch)
[![Code Climate](https://codeclimate.com/github/ubpb/metacrunch/badges/gpa.svg)](https://codeclimate.com/github/ubpb/metacrunch)
[![Test Coverage](https://codeclimate.com/github/ubpb/metacrunch/badges/coverage.svg)](https://codeclimate.com/github/ubpb/metacrunch/coverage)
[![CircleCI](https://circleci.com/gh/ubpb/metacrunch.svg?style=svg)](https://circleci.com/gh/ubpb/metacrunch)

metacrunch is a simple and lightweight data processing and ETL ([Extract-Transform-Load](http://en.wikipedia.org/wiki/Extract,_transform,_load))
toolkit for Ruby.


Installation
------------

```
$ gem install metacrunch
```

*Note: When upgrading from metacrunch 3.x, there are some breaking changes you need to address. See the [notes below](#upgrading) for details.*


Creating ETL jobs
-----------------

The basic idea behind an ETL job in metacrunch is the concept of a data processing pipeline. Each ETL job reads data from a **source** (extract step), runs one or more **transformations** (transform step) on the data and finally loads the transformed data to a **destination** (load step).

metacrunch gives you a simple DSL ([Domain-specific language](https://en.wikipedia.org/wiki/Domain-specific_language)) to define and run ETL jobs in Ruby. Just create a text file with the extension `.metacrunch` and [run it](#running-etl-jobs) with the provided `metacrunch` CLI command. *Note: The file extension doesn't really matter but you should avoid `.rb` to not loading them by mistake from another Ruby component.*

Let's walk through the main steps of creating ETL jobs with metacrunch. For a collection of working examples check out our [metacrunch-demo](https://github.com/ubpb/metacrunch-demo) repository.

### It's Ruby

Every `.metacrunch` job is a regular Ruby file and you can use any valid Ruby code like declaring methods, classes, variables, requiring other Ruby 
files and so on. 

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

### Defining a source

A source is an object that reads data (e.g. from a file or an external system) into the metacrunch processing pipeline. Implementing sources is easy – a source is a Ruby `Enumerable` (any object that responds to the `#each` method). For more information on how to implement sources [see notes below](#implementing-sources).

You must declare a source to allow a job to run.

A source iterates over it's elements and yields data object by data object into the transformation pipeline, starting with the first transformation.

```ruby
# File: my_etl_job.metacrunch

source [1,2,3,4]
# or ...
source Metacrunch::File::Source.new(ARGV)
# or ...
source MySource.new
```

### Defining transformations

To process, transform or manipulate data use the `#transformation` hook. A transformation is implemented with a `callable` object (any Ruby object that responds to `#call`. E.g. a `Proc`). To learn more about transformations check the section about [implementing transformations](#implementing-transformations) below.

The *current data object* (the current object yielded by the source) will be passed to the first transformation as a parameter. The return value of a transformation will then be passed to the next transformation and so on.

There are two exceptions to that rule:

* If you return `nil` the current data object will be dismissed and the next transformation won't be called. The process continues with the next data object that is yielded by the source and the first transformation.
* If you return an `Enumerator` the object will be expanded and the following transformations will be called with each element of the `Enumerator`.

```ruby
# File: my_etl_job.metacrunch

# Array implements #each and therefore is a valid source
source [1,2,3,4,5,6,7,8,9]

# A transformation is implemented with a `callable` object (any 
# object that responds to #call).
# Lambdas responds to #call
transformation ->(number) {
  # Called for each data object that has been read by a source.
  # You must return the data to keep it in the pipeline. Dismiss the
  # data conditionally by returning nil.
  number if number.odd?
}

transformation ->(odd_number) {
  odd_number * 2
}

# MyTransformation implements #call
transformation MyTransformation.new
```

### Using a transformation buffer

Sometimes it is useful to buffer data between transformation steps to allow a transformation to work on larger bulks of data. metacrunch uses a simple transformation buffer to achieve this.

To use a transformation buffer add the `:buffer` option to your transformation. You can pass a positive integer value as a buffer size, or as an advanced option you can pass a `Proc` object. The buffer flushes every time the buffer reaches the given size or if the `Proc` returns `true`.

```ruby
# File: my_etl_job.metacrunch

source 1..95 # A range responds to #each and is a valid source

# A buffer with a fixed size
transformation ->(bulk) { 
  # this transformation is called when the buffer 
  # is filled with 10 objects or if the source has
  # yielded the last data object.
  # bulk would be: [1,...,10], [11,...,20], ..., [91,...,95]
}, buffer: 10

# A buffer that uses a Proc
transformation ->(bulk) { 
  # Called when the buffer `Proc` returns `true`
}, buffer: -> {
  true if some_condition
}
```

### Defining a destination

A destination is an object that writes the transformed data to an external system. Implementing destinations is easy – [see notes below](#implementing-destinations). A destination receives the return value from the last transformation as a parameter if the return value from the last transformation was not `nil`.

Using destinations is optional. In most cases using the last transformation to write the data to an external system is fine. Destinations are useful if the required code is more complex.

```ruby
# File: my_etl_job.metacrunch

destination MyDestination.new
```

### Pre/Post process 

To run arbitrary code before the first transformation is run on the first data object use the `#pre_process` hook. To run arbitrary code after the last transformation is run on the last data object use `#post_process`. Like transformations, `#post_process` and `#pre_process` must be implemented using a `callable` object.

```ruby
pre_process -> {
  # Lambdas responds to #call
}

# MyCallable class defines #call
post_process MyCallable.new
```

### Defining job options

metacrunch has build-in support to parameterize jobs. Using the `options` hook you can declare options that can be set/overridden by the CLI when [running your jobs](#running-etl-jobs). 

```ruby
# File: my_etl_job.metacrunch

options do
  add :log_level, "-l", "--log-level LEVEL", "Log level (debug,info,warn,error)", default: "info" 
  add :database_url, "-d", "--database URL", "Database connection URL", required: true
end

# Prints out 'info'
echo options[:log_level]
```

In this example we declare two options `log_level` and `database_url`. `log_level` defaults to `info`, whereas `database_url` has no default and is required. In your job file you can access the option values using the `options` Hash. E.g. `options[:log_level]`.

To set/override these options use the command line.

```
$ metacrunch my_etl_job.metacrunch --log-level debug
```

This will set the `options[:log_level]` to `debug`.

To get a list of available options for a job, use `--help` on the command line.

```
$ metacrunch my_etl_job.metacrunch --help

Job options:
    -l, --log-level LEVEL            Log level (debug,info,warn,error)
                                     DEFAULT: info
    -d, --database URL               Database connection URL
                                     REQUIRED
```

To learn more about defining options take a look at the [reference below](#defining-job-options).

### Require non-option arguments

All non-option arguments that get passed to the job when running are available to the `ARGV` constant. If your job requires such arguments (e.g. if you work with a list of files) you can require it.

```ruby
# File: my_etl_job.metacrunch

options(require_args: true) do
  # ...
end

```


Running ETL jobs
----------------

metacrunch comes with a handy command line tool. In a terminal use


```
$ metacrunch my_etl_job.metacrunch
```

to run a job.

If you use [Bundler](http://bundler.io) to manage dependencies for your jobs make sure to change into the directory where your Gemfile is (or set BUNDLE_GEMFILE environment variable) and run metacrunch with `bundle exec`.

```
$ bundle exec metacrunch my_etl_job.metacrunch
```

In your job file use `Bundler.require` to require the dependencies from your `Gemfile`.

```ruby
# File: my_etl_job.metacrunch
Bundler.require
```

Use the following syntax to run a metacrunch job

```
$ [bundle exec] metacrunch [options] JOB_FILE [job-options] [ARGS...]
```


Implementing sources
--------------------

A metacrunch source is any Ruby `Enumerable` object (an object that responds to the `#each` method) that yields data objects one by one. 

The data is usually a `Hash` instance, but could be other structures as long as the rest of your pipeline is expecting it.

Any `Enumerable` object (e.g. `Array`) responds to `#each` and can be used as a source in metacrunch. 

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

A metacrunch transformation is implemented as a `callable` object. A `callable` in Ruby is any object that responds to the `#call` method. 

`Proc`s in Ruby respond to `#call`. They can be used to implement transformations inline.

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

A destination is any Ruby object that responds to `#write(data)` and `#close`.

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

Official extension packages
---------------------------

* [metacrunch-db](https://github.com/ubpb/metacrunch-db): SQL Database package
* [metacrunch-file](https://github.com/ubpb/metacrunch-file): File package
* [metacrunch-elasticsearch](https://github.com/ubpb/metacrunch-elasticsearch): [Elasticsearch](https://www.elastic.co) package
* [metacrunch-redis](https://github.com/ubpb/metacrunch-redis): [Redis](https://redis.io) package
* [metacrunch-marcxml](https://github.com/ubpb/metacrunch-marcxml): [MARCXML](http://www.loc.gov/standards/marcxml/) package

Upgrading
---------

#### 3.x -> 4.x

When upgrading from metacrunch 3.x, there are some breaking changes you need to address.

* There is now only one `source` and `destination`. If you have more than one in your job file the last definition will used.
* There is no `transformation_buffer` anymore. Instead set `buffer` as an option to `transformation`.
* `transformation`, `pre_process` and `post_process` can't be implemented using a block anymore. Always use a `callable` (E.g. Lambda, Proc or any object responding to `#call`).
* When running jobs via the CLI you do not need to separate the arguments passed to metacrunch from the arguments passed to the job with `@@`.
* The `args` function used to get the non-option arguments passed to a job has been removed. Use `ARGV` instead.
* `Metacrunch::Db` classes have been moved into the [metacrunch-db](https://github.com/ubpb/metacrunch-db) gem package.
* `Metacrunch::Redis` classes have been moved into the [metacrunch-redis](https://github.com/ubpb/metacrunch-redis) gem package.
* `Metacrunch::File` classes have been moved into the [metacrunch-file](https://github.com/ubpb/metacrunch-file) gem package.

License
-------

metacrunch is available at [github](https://github.com/ubpb/metacrunch) under [MIT license](https://github.com/ubpb/metacrunch/blob/master/License.txt).
