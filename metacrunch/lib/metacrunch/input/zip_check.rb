# frozen_string_literal: true

require "shellwords"

module Metacrunch
  class Input
    # Refuses a ZIP archive before its first document when it is a document
    # itself (Office, EPUB, OpenDocument: a reader would get its XML parts)
    # or when it holds documents metacrunch cannot read (encrypted, or
    # compressed with another method than deflate). Internal.
    module ZipCheck

      # A kind of ZIP package: marker and part are entry names, a part
      # ending with "/" a directory of entries.
      Package = Data.define(:label, :marker, :part, :advice, :tool) do
        def match?(names)
          names.include?(marker) && names.any? { part.end_with?("/") ? it.start_with?(part) : it == part }
        end
      end

      # In the order they are checked: an EPUB may also have the manifest
      # of OpenDocument.
      PACKAGES = [
        Package.new("is an Excel workbook", "[Content_Types].xml", "xl/", "save it as CSV", nil),
        Package.new("is a Word document", "[Content_Types].xml", "word/", "unpack it", "unzip"),
        Package.new("is a PowerPoint presentation", "[Content_Types].xml", "ppt/", "unpack it", "unzip"),
        Package.new("is an EPUB book", "mimetype", "META-INF/container.xml", "unpack it", "unzip"),
        Package.new("is an OpenDocument file", "mimetype", "META-INF/manifest.xml", "unpack it", "unzip")
      ].freeze

      ENCRYPTED_DIRECTORY = 0x2000
      # The tool for encrypted entries and other methods, and its command.
      SEVEN_ZIP = ["7z", "7z x"].freeze

      module_function

      # file: the path when the archive is the outer layer of a file, for
      # hints with a command, else nil.
      def check(zip, name, file)
        names = zip.entries.map(&:name)
        package = PACKAGES.find { it.match?(names) }
        raise InputError, message(name, package.label, package.advice, file, package.tool) if package
        if zip.entries.any? { it.flags.anybits?(ENCRYPTED_DIRECTORY) }
          raise InputError, message(name, "is encrypted", "decrypt it", file, *SEVEN_ZIP)
        end

        zip.entries.each { check_entry(it, name, file) if it.document? }
        nil
      end

      def check_entry(entry, name, file)
        name = "#{name}:#{entry.name}"
        raise InputError, message(name, "is encrypted", "decrypt it", file, *SEVEN_ZIP) if entry.encrypted?
        return if Zip::READABLE.include?(entry.compression)

        label = "is compressed with #{Zip.method_name(entry.compression)}"
        raise InputError, message(name, label, "unpack it", file, *SEVEN_ZIP)
      end

      # tool: nil for advice without one. With file, the hint is the
      # command with the path; else it names the tool.
      def message(name, label, advice, file, tool = nil, command = tool)
        text = "#{name}: #{label}, which metacrunch cannot read; #{advice} first"
        return text unless tool

        "#{text}, e.g. #{file ? "#{command} #{Shellwords.escape(file)}" : "with #{tool}"}"
      end

    end
  end
end
