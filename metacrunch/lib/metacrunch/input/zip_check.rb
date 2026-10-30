# frozen_string_literal: true

require "shellwords"

module Metacrunch
  class Input
    # Refuses a ZIP archive before its first document when it holds
    # documents metacrunch cannot read: encrypted, or compressed with a
    # method other than stored or deflate. What the documents are is not
    # checked: an Office file is a zip archive like any other. Internal.
    module ZipCheck

      ENCRYPTED_DIRECTORY = 0x2000
      # The tool for encrypted entries and other methods, and its command.
      SEVEN_ZIP = ["7z", "7z x"].freeze

      module_function

      # file: the path when the archive is the outer layer of a file, for
      # hints with a command, else nil.
      def check(zip, name, file)
        if zip.entries.any? { it.flags.anybits?(ENCRYPTED_DIRECTORY) }
          raise InputError, message(name, "is encrypted", "decrypt it", file)
        end

        zip.entries.each { check_entry(it, name, file) if it.document? }
        nil
      end

      def check_entry(entry, name, file)
        name = "#{name}:#{entry.name}"
        raise InputError, message(name, "is encrypted", "decrypt it", file) if entry.encrypted?
        return if Zip::READABLE.include?(entry.compression)

        message = message(name, "is compressed with #{Zip.method_name(entry.compression)}", "unpack it", file)
        raise InputError, message
      end

      # With file, the hint is 7z's command with the path; else it names
      # the tool.
      def message(name, label, advice, file)
        tool, command = SEVEN_ZIP
        "#{name}: #{label}, which metacrunch cannot read; #{advice} first, e.g. " \
          "#{file ? "#{command} #{Shellwords.escape(file)}" : "with #{tool}"}"
      end

    end
  end
end
