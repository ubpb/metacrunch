# frozen_string_literal: true

module Metacrunch
  class Input
    # Tells gzip, tar and the formats metacrunch cannot read from the first
    # bytes of a document. Internal.
    module Formats

      # How many bytes detection looks at: tar's magic ends at byte 262.
      PEEK = 262
      GZIP = "\x1F\x8B\x08".b
      TAR = "ustar".b
      TAR_AT = 257

      # A format metacrunch recognizes but cannot read.
      Unsupported = Data.define(:pattern, :label, :advice, :tool) do
        def match?(head) = pattern.match?(head)

        # file: what the hint names, a path or a member's name; nil for
        # stdin and IOs.
        def message(name, file)
          "#{name}: #{label}, which metacrunch cannot read; #{advice} first, " \
            "e.g. #{tool} #{file || "FILE"} | metacrunch run job.rb -i -"
        end
      end

      UNSUPPORTED = [
        Unsupported.new(/\ABZh[1-9](?:1AY&SY|\x17rE8P\x90)/n, "is bzip2 compressed", "decompress it", "bzip2 -dc"),
        Unsupported.new(/\A\xFD7zXZ\x00/n, "is xz compressed", "decompress it", "xz -dc"),
        Unsupported.new(/\A\x28\xB5\x2F\xFD/n, "is zstd compressed", "decompress it", "zstd -dc"),
        Unsupported.new(/\APK(?:\x03\x04|\x05\x06)/n, "is a zip archive", "unpack it", "unzip -p")
      ].freeze

      module_function

      # :gzip, :tar, :plain or an Unsupported, for head: the first PEEK
      # bytes of a document (fewer for a short one).
      def detect(head)
        return :gzip if head.start_with?(GZIP)
        return :tar if head.byteslice(TAR_AT, TAR.bytesize) == TAR

        UNSUPPORTED.find { it.match?(head) } || :plain
      end

    end
  end
end
