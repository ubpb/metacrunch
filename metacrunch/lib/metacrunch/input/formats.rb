# frozen_string_literal: true

require "shellwords"

module Metacrunch
  class Input
    # Tells gzip, tar, zip and the formats metacrunch cannot read from the
    # first bytes of a document. Internal.
    module Formats

      # How many bytes detection looks at: tar's magic ends at byte 262.
      PEEK = 262
      GZIP = "\x1F\x8B\x08".b
      # A local file header, or the end record of an empty archive.
      ZIP = ["PK\x03\x04".b, "PK\x05\x06".b].freeze
      TAR = "ustar".b
      TAR_AT = 257
      # A tar header starts with the member's name, 100 bytes padded with
      # NUL. A "\n" in it before any NUL means: no tar.
      TAR_NAME = 100
      NEWLINE = "\n".b
      NUL = "\0".b

      # A format metacrunch recognizes but cannot read, by its magic bytes.
      # pipe: false for a tool that cannot sit in a pipe; its hint names
      # the tool only.
      Unsupported = Data.define(:magics, :label, :advice, :tool, :pipe) do
        def initialize(magics:, label:, advice:, tool:, pipe: true) = super

        def match?(head) = magics.any? { head.start_with?(it) }

        # True if head could be the start of one of the magics.
        def possible?(head) = magics.any? { it.start_with?(head) }

        # file: the path of the file whose outer layer the format is; nil
        # for stdin, IOs and documents inside gzip, tar or zip, where a
        # command on a file would decompress the wrong layer.
        def message(name, file)
          "#{name}: #{label}, which metacrunch cannot read; #{advice} first, e.g. #{hint(name, file)}"
        end

        def hint(name, file)
          return "with #{tool}" unless pipe
          return "#{tool} #{Shellwords.escape(file)} | metacrunch run job.rb -i -" if file
          return "... | #{tool} | metacrunch run job.rb -i -" if name == STDIO

          "with #{tool}"
        end
      end

      BZIP2 = ("1".."9").flat_map { |level| ["BZh#{level}1AY&SY", "BZh#{level}\x17rE8P\x90"] }.map(&:b).freeze

      # The first part of a split archive (zip -s); also raised for the
      # last part, whose end record names another disk.
      SPLIT = Unsupported.new(magics: ["PK\x07\x08".b], label: "is part of a split zip archive",
                              advice: "join the parts", tool: "zip -s 0", pipe: false)

      UNSUPPORTED = [
        Unsupported.new(BZIP2, "is bzip2 compressed", "decompress it", "bzip2 -dc"),
        Unsupported.new(["\xFD7zXZ\x00".b], "is xz compressed", "decompress it", "xz -dc"),
        Unsupported.new(["\x28\xB5\x2F\xFD".b], "is zstd compressed", "decompress it", "zstd -dc"),
        SPLIT
      ].freeze

      module_function

      # :gzip, :tar, :zip, :plain or an Unsupported, for head: the first PEEK
      # bytes of a document, or fewer. complete: head is all there will be
      # (PEEK bytes, or the end of the document). Without it, nil means that
      # more bytes are needed to decide, so a slow pipe is not waited for
      # longer than its first line.
      def detect(head, complete: true)
        return :gzip if head.start_with?(GZIP)
        return :tar if head.byteslice(TAR_AT, TAR.bytesize) == TAR
        return :zip if ZIP.any? { head.start_with?(it) }

        unsupported = UNSUPPORTED.find { it.match?(head) }
        return unsupported if unsupported
        return :plain if complete
        return if [GZIP, *ZIP].any? { it.start_with?(head) } || UNSUPPORTED.any? { it.possible?(head) } || tar?(head)

        :plain
      end

      # True if head, shorter than PEEK, could still be a tar header.
      def tar?(head)
        newline = head.byteindex(NEWLINE)
        return true unless newline && newline < TAR_NAME

        nul = head.byteindex(NUL)
        nul && nul < newline
      end

    end
  end
end
