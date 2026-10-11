# metacrunch-ng encrypted credentials (sub-project 6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Job parameters read secrets from encrypted per-environment files in `.metacrunch/` (`credential: "fis.api_key"`), and `metacrunch credentials edit|show|rotate` manages those files.

**Architecture:** `Credentials::Key` and `Credentials::Box` implement the file format: AES-256-GCM from OpenSSL, YAML inside. `Credentials::Location` finds the directory, the file of an environment and the key. `Credentials::Store` decrypts lazily, on the first `dig`. `Params#bind_argv` asks the store only when neither the command line nor `env:` gives a value, and redacts secret parameters. `JobCommand` and `Job#run` build the store. `Cli::CredentialsCommand` with `Credentials::Editor` edits, shows and rotates the files. The engine does not change.

**Tech Stack:** Ruby 4.0, standard library and default gems (`openssl`, `yaml`, `securerandom`, `shellwords`, `tmpdir`, `fileutils`), Minitest 6, SimpleCov, RuboCop with rubocop-ubpb `ruby.yml`.

**Spec:** `docs/superpowers/specs/2026-10-11-metacrunch-ng-credentials-design.md` (builds on the specs of sub-projects 1 and 2 in the same directory)

## Global Constraints

- `required_ruby_version = ">= 4.0"`, gem version stays `5.0.0.pre`.
- Runtime dependency: `logger` only. No new gems. `base64` is a bundled gem since Ruby 3.4 and cannot be required under Bundler without a dependency: strict Base64 uses `pack("m0")` and `unpack1("m0")`.
- Library files are loaded with `require_relative` from `lib/metacrunch.rb`. The editor and the command are CLI-only: `lib/metacrunch/cli.rb` requires them.
- Every Ruby file starts with `# frozen_string_literal: true` (also test fixtures and scripts written by tests).
- No secret value and no key ever appears in an exception message, a log line or an `inspect` output. Messages name files, paths and key sources instead.
- File names: `credentials[.ENV].yml.enc` and `master[.ENV].key` in a `.metacrunch/` directory. Variables: `METACRUNCH_MASTER_KEY`, `METACRUNCH_ENV`, `METACRUNCH_CREDENTIALS`. Environment names match `\A[a-z0-9_-]+\z`.
- Credentials files get mode 0644, key files 0600; both are written atomically (temporary file in the same directory, then `File.rename`).
- The library never calls `exit`. Commands never use `$stdin`, `$stdout` or `$stderr` directly; they use the streams and the `env` injected into `Metacrunch::Cli`. The `credentials` command takes the working directory from `Dir.pwd`.
- Inline runs keep their cost: `bundle exec ruby -Ilib bench/executor.rb inline` stays within 5 % of about 62 ns per step and record, 4.0 allocations per record.
- Lint: `bundle exec rubocop` is clean at the end of every task (`bundle exec rubocop -a` may fix layout). Metrics cops are disabled by ruby.yml.
- Style that ruby.yml enforces:
  - double quotes, also inside interpolation;
  - `{a: 1}` without spaces inside the braces;
  - `[:a, :b]` and `["a", "b"]` instead of `%i[]` and `%w[]`;
  - blank lines at the start and end of class and module bodies, except for pure namespaces;
  - lines of at most 120 characters;
  - at most 3 assertions per Minitest test, and a blank line before the first assertion;
  - `rescue Exception` only with `# rubocop:disable Lint/RescueException` on that line.
- Tests:
  - Single file: `bundle exec ruby -w -Ilib -Itest <file>`.
  - Full suite with coverage thresholds (95 % lines, 90 % branches) and lint: `bundle exec rake`.
  - Minitest 6 has no `stub`; tests replace singleton methods with `Override#override` (`test/support/override.rb`).
  - Tests that need files use `in_tmpdir` (Task 2), which yields the real path: macOS links `/var` to `/private/var`, and the credentials code resolves links.
  - Tests never read the developer's `~/.metacrunch/`: in-process CLI tests get an `env` without `HOME` unless they set it, subprocess tests set `HOME` to a temporary directory.
- Repo docs, code comments and commit messages are in English.
- Every commit message ends with these two lines:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
  ```

## Review Focus

These are inputs and conditions the spec implies but does not spell out, ordered by how likely they are to bite a user first. Each one has a test in the task named in brackets.

1. **Values that YAML does not read as Strings** (`password: no`, `pin: 0123`, `token: 1234` for a String parameter): YAML 1.1 makes them `false`, 83 and 1234. The run fails with the value hidden and the hint to quote it. It never converts silently. [Task 4]
2. **Files edited or transported by other tools:** CRLF line ends, trailing blank lines, a key with uppercase hex or surrounding spaces (pasted into a CI secret). All are accepted. [Task 1]
3. **Non-ASCII secrets** (`pässwörd`): they survive `edit`, encryption and the run byte for byte. [Tasks 1, 7]
4. **A GUI editor that returns at once** (`EDITOR=code` without `--wait`): nothing is rewritten, and the message says how to make the editor wait. [Task 7]
5. **No `HOME` (cron, minimal containers) and a relative `--credentials`:** no crash; the relative directory is taken from the working directory. [Task 2]

---

## File Structure

```
lib/metacrunch/errors.rb                    CredentialsError                                Task 1
lib/metacrunch/credentials.rb               constants, names, environment, YAML, write;     Tasks 1, 3
                                            Credentials.store
lib/metacrunch/credentials/key.rb           Key                                             Task 1
lib/metacrunch/credentials/box.rb           Box (format v1, AES-256-GCM)                    Task 1
lib/metacrunch/credentials/location.rb      Location (directory, files, key)                Task 2
lib/metacrunch/credentials/store.rb         Store (lazy dig, origin, missing)               Task 3
lib/metacrunch/credentials/editor.rb        Editor, EditAborted                             Task 7
lib/metacrunch.rb                           requires                                        Tasks 1, 2, 3
lib/metacrunch/params.rb                    credential:, secrets, bind_argv(credentials:,   Task 4
                                            warn:), messages
lib/metacrunch/job.rb                       Job#file, Job#run builds the store              Task 5
lib/metacrunch/loader.rb                    sets Job#file                                   Task 5
lib/metacrunch/cli/command.rb               #parse hook, #credentials_options               Task 5
lib/metacrunch/cli/job_command.rb           -e, --credentials, store in build_pipeline      Task 5
lib/metacrunch/cli/credentials.rb           CredentialsCommand (show, edit, rotate)         Tasks 6, 7, 8
lib/metacrunch/cli.rb                       COMMANDS, usage width, requires                 Tasks 6, 7
test/support/credentials_helper.rb          tmp projects, SECRET_JOB, scripted editor       Tasks 2, 5, 7
Readme.md, CHANGELOG.md                     documentation                                   Task 9
docs/superpowers/specs/...credentials...    layout line, status                             Tasks 1, 9
```

---

### Task 1: Key, file format and YAML

**Files:**
- Modify: `lib/metacrunch/errors.rb`
- Create: `lib/metacrunch/credentials.rb`
- Create: `lib/metacrunch/credentials/key.rb`
- Create: `lib/metacrunch/credentials/box.rb`
- Modify: `lib/metacrunch.rb` (requires)
- Modify: `docs/superpowers/specs/2026-10-11-metacrunch-ng-credentials-design.md` (layout line in section 6)
- Test: `test/unit/credentials_key_test.rb`, `test/unit/credentials_box_test.rb`, `test/unit/credentials_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Metacrunch::CredentialsError < ParamError`
  - `Metacrunch::Credentials::DIRECTORY = ".metacrunch"`, `KEY_VARIABLE = "METACRUNCH_MASTER_KEY"`, `ENVIRONMENT_VARIABLE = "METACRUNCH_ENV"`, `DIRECTORY_VARIABLE = "METACRUNCH_CREDENTIALS"`, `ENVIRONMENT_NAME`
  - `Credentials.file_name(environment) -> String`, `Credentials.key_name(environment) -> String` (environment: String or nil)
  - `Credentials.environment(option, env) -> String | nil` (raises `CredentialsError` for invalid names)
  - `Credentials.present(value) -> value | nil` (nil for nil and empty Strings)
  - `Credentials.load_yaml(text, path) -> Hash` (raises `CredentialsError`)
  - `Credentials.write(path, content, perm:) -> nil` (atomic)
  - `Credentials::Key.generate(source: "a new key") -> Key`, `Key.parse(text, source:) -> Key`, `#bytes` (32-byte binary String), `#hex` (64 lowercase hex), `#source` (String)
  - `Credentials::Box.seal(plaintext, key) -> String` (file content), `Box.unseal(content, key, path:) -> String` (UTF-8 plaintext)

- [ ] **Step 1: Write the failing tests for Key**

`test/unit/credentials_key_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsKeyTest < Minitest::Test

  Key = Metacrunch::Credentials::Key
  HEX = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

  def test_generates_32_random_bytes
    first = Key.generate
    second = Key.generate

    assert_equal 32, first.bytes.bytesize
    refute_equal first.bytes, second.bytes
    assert_match(/\A\h{64}\z/, first.hex)
  end

  def test_parses_hex_with_surrounding_whitespace_and_upper_case
    assert_equal HEX, Key.parse("  #{HEX.upcase}\r\n", source: "master.key").hex
  end

  def test_rejects_anything_but_64_hex_characters
    texts = ["", HEX[1..], "#{HEX}0", HEX.sub("0", "g"), "#{HEX[0, 32]} #{HEX[32..]}"]
    messages = texts.map do |text|
      assert_raises(Metacrunch::CredentialsError) { Key.parse(text, source: "METACRUNCH_MASTER_KEY") }.message
    end

    assert_equal ["invalid key from METACRUNCH_MASTER_KEY: expected 64 hex characters"], messages.uniq
  end

  def test_inspect_and_to_s_name_the_source_but_never_the_key
    key = Key.parse(HEX, source: "/p/.metacrunch/master.key")

    assert_equal "#<Metacrunch::Credentials::Key from /p/.metacrunch/master.key>", key.inspect
    refute_includes key.to_s, HEX
  end

end
```

- [ ] **Step 2: Write the failing tests for Box**

`test/unit/credentials_box_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsBoxTest < Minitest::Test

  Box = Metacrunch::Credentials::Box
  Key = Metacrunch::Credentials::Key
  PATH = "/p/.metacrunch/credentials.yml.enc"
  NOT_CREDENTIALS = "not a metacrunch credentials file: #{PATH}".freeze

  REJECTED = {
    "" => NOT_CREDENTIALS,
    "a: 1\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\nnot base64!\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\nc2hvcnQ=\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\nAAAA\nAAAA\n" => NOT_CREDENTIALS,
    "metacrunch credentials v2\nAAAA\n" => "unsupported credentials format in #{PATH}: v2"
  }.freeze

  def setup
    @key = Key.generate
  end

  def test_unseals_what_it_sealed_as_utf8
    plaintext = Box.unseal(Box.seal("fis:\n  api_key: pässwörd\n", @key), @key, path: PATH)

    assert_equal "fis:\n  api_key: pässwörd\n", plaintext
    assert_equal Encoding::UTF_8, plaintext.encoding
  end

  def test_seals_empty_text
    assert_equal "", Box.unseal(Box.seal("", @key), @key, path: PATH)
  end

  def test_writes_a_header_and_one_line_of_base64
    header, body, *rest = Box.seal("a: 1\n", @key).lines(chomp: true)

    assert_equal ["metacrunch credentials v1", []], [header, rest]
    assert_match(%r{\A[A-Za-z0-9+/]+=*\z}, body)
  end

  def test_every_seal_uses_a_new_iv
    refute_equal Box.seal("a: 1\n", @key), Box.seal("a: 1\n", @key)
  end

  def test_a_wrong_key_fails_and_names_its_source
    content = Box.seal("a: 1\n", @key)
    other = Key.generate(source: "METACRUNCH_MASTER_KEY")
    error = assert_raises(Metacrunch::CredentialsError) { Box.unseal(content, other, path: PATH) }

    assert_equal "cannot decrypt #{PATH}: wrong key or modified file (key from METACRUNCH_MASTER_KEY)", error.message
  end

  def test_a_changed_byte_in_iv_tag_or_ciphertext_fails
    header, body = Box.seal("a: 1\n", @key).lines(chomp: true)
    raw = body.unpack1("m0")
    failures = [0, 12, 28].count do |index|
      changed = raw.dup
      changed.setbyte(index, changed.getbyte(index) ^ 1)
      Box.unseal("#{header}\n#{[changed].pack("m0")}\n", @key, path: PATH)
      false
    rescue Metacrunch::CredentialsError
      true
    end

    assert_equal 3, failures
  end

  def test_rejects_content_that_is_no_credentials_file
    REJECTED.each do |content, message|
      error = assert_raises(Metacrunch::CredentialsError) { Box.unseal(content, @key, path: PATH) }

      assert_equal message, error.message, content.inspect
    end
  end

  def test_reads_crlf_line_ends_and_trailing_blank_lines
    content = "#{Box.seal("a: 1\n", @key).gsub("\n", "\r\n")}\r\n\r\n"

    assert_equal "a: 1\n", Box.unseal(content, @key, path: PATH)
  end

end
```

- [ ] **Step 3: Write the failing tests for the module functions**

`test/unit/credentials_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class CredentialsTest < Minitest::Test

  Credentials = Metacrunch::Credentials
  PATH = "/p/.metacrunch/credentials.yml.enc"

  YAML_ERRORS = {
    "a: [\n" => "invalid YAML in #{PATH} at line 2, column 1",
    "- a\n" => "#{PATH} must contain a mapping at the top level",
    "d: 2026-10-11\n" => "unsupported value in #{PATH}: Date (quote it)",
    "s: :sym\n" => "unsupported value in #{PATH}: Symbol (quote it)",
    "a: *missing\n" => "invalid YAML in #{PATH}"
  }.freeze

  def test_names_files_and_keys_per_environment
    assert_equal ["credentials.yml.enc", "master.key"], [Credentials.file_name(nil), Credentials.key_name(nil)]
    assert_equal ["credentials.production.yml.enc", "master.production.key"],
                 [Credentials.file_name("production"), Credentials.key_name("production")]
  end

  def test_the_environment_comes_from_the_option_then_the_variable
    env = {"METACRUNCH_ENV" => "production"}

    assert_equal "staging", Credentials.environment("staging", env)
    assert_equal "production", Credentials.environment(nil, env)
    assert_nil Credentials.environment("", {"METACRUNCH_ENV" => ""})
  end

  def test_environment_names_are_limited_to_a_to_z_digits_underscore_and_dash
    messages = ["Production", "prod.x", "../x", "a b"].map do |name|
      assert_raises(Metacrunch::CredentialsError) { Credentials.environment(name, {}) }.message
    end

    assert_equal "invalid environment \"Production\": use a-z, 0-9, _ and -", messages.first
    assert_equal 4, messages.grep(/\Ainvalid environment /).size
  end

  def test_reads_plain_yaml_types_and_aliases
    data = Credentials.load_yaml("x: &k v\ny: *k\nn: 1\nok: true\nl: [a, b]\n", PATH)

    assert_equal({"x" => "v", "y" => "v", "n" => 1, "ok" => true, "l" => ["a", "b"]}, data)
  end

  def test_a_file_with_only_comments_is_empty
    assert_equal({}, Credentials.load_yaml("# nothing yet\n", PATH))
  end

  def test_reports_yaml_errors_by_position_only
    YAML_ERRORS.each do |text, message|
      error = assert_raises(Metacrunch::CredentialsError) { Credentials.load_yaml(text, PATH) }

      assert_equal message, error.message, text
    end
  end

  def test_yaml_errors_do_not_quote_the_content
    error = assert_raises(Metacrunch::CredentialsError) { Credentials.load_yaml("password: \"geheim\n", PATH) }

    assert_equal "invalid YAML in #{PATH} at line 1, column 11", error.message
  end

  def test_write_replaces_a_file_atomically_with_the_given_mode
    Dir.mktmpdir do |dir|
      path = File.join(dir, "master.key")
      File.write(path, "old", perm: 0o644)
      Credentials.write(path, "new\n", perm: 0o600)

      assert_equal ["new\n", 0o600], [File.read(path), File.stat(path).mode & 0o777]
      assert_equal ["master.key"], Dir.children(dir)
    end
  end

  def test_write_leaves_no_temporary_file_when_it_fails
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      Dir.mkdir(target)

      assert_raises(SystemCallError) { Credentials.write(target, "x", perm: 0o600) }
      assert_equal ["target"], Dir.children(dir)
    end
  end

end
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require_relative it }' test/unit/credentials_key_test.rb test/unit/credentials_box_test.rb test/unit/credentials_test.rb`
Expected: errors `uninitialized constant Metacrunch::Credentials` (and `Metacrunch::CredentialsError`).

- [ ] **Step 5: Add the error class**

In `lib/metacrunch/errors.rb`, after `class ParamError < Error; end`:

```ruby

  # Credentials could not be read: no key, a wrong key, a damaged file,
  # invalid YAML or an invalid environment name. A ParamError, because it
  # happens while parameters are bound; the CLI exits with 2.
  class CredentialsError < ParamError; end
```

- [ ] **Step 6: Write `lib/metacrunch/credentials.rb`**

```ruby
# frozen_string_literal: true

require "yaml"

module Metacrunch
  # Encrypted credentials for job parameters: one file and one key per
  # environment in a .metacrunch/ directory (see the Readme, "Credentials").
  module Credentials

    DIRECTORY = ".metacrunch"
    KEY_VARIABLE = "METACRUNCH_MASTER_KEY"
    ENVIRONMENT_VARIABLE = "METACRUNCH_ENV"
    DIRECTORY_VARIABLE = "METACRUNCH_CREDENTIALS"
    ENVIRONMENT_NAME = /\A[a-z0-9_-]+\z/

    module_function

    def file_name(environment) = environment ? "credentials.#{environment}.yml.enc" : "credentials.yml.enc"

    def key_name(environment) = environment ? "master.#{environment}.key" : "master.key"

    # The environment from the option (-e), else METACRUNCH_ENV; nil if
    # neither is set. Empty values count as unset.
    def environment(option, env)
      name = present(option) || present(env[ENVIRONMENT_VARIABLE])
      return if name.nil?
      return name if ENVIRONMENT_NAME.match?(name)

      raise CredentialsError, "invalid environment #{name.inspect}: use a-z, 0-9, _ and -"
    end

    def present(value) = (value unless value.nil? || value.empty?)

    # The Hash in decrypted YAML. Errors name the position, never the
    # content, because Psych messages can quote it.
    def load_yaml(text, path)
      data = YAML.safe_load(text, aliases: true)
      return {} if data.nil?
      return data if data.is_a?(Hash)

      raise CredentialsError, "#{path} must contain a mapping at the top level"
    rescue Psych::DisallowedClass => e
      raise CredentialsError, "unsupported value in #{path}: #{e.message[/unspecified class: (\S+)/, 1]} (quote it)"
    rescue Psych::SyntaxError => e
      raise CredentialsError, "invalid YAML in #{path} at line #{e.line}, column #{e.column}"
    rescue Psych::Exception
      raise CredentialsError, "invalid YAML in #{path}"
    end

    # Writes content to path atomically: to a temporary file next to it,
    # with mode perm, then renamed over path.
    def write(path, content, perm:)
      temp = "#{path}.#{Process.pid}.tmp"
      File.open(temp, "w", perm) { it.write(content) }
      File.chmod(perm, temp)
      File.rename(temp, path)
      nil
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
    end

  end
end
```

- [ ] **Step 7: Write `lib/metacrunch/credentials/key.rb`**

```ruby
# frozen_string_literal: true

require "securerandom"

module Metacrunch
  module Credentials
    # A 256-bit key. source says where it came from (METACRUNCH_MASTER_KEY
    # or the path of a key file), for messages; inspect never shows the key.
    class Key

      HEX = /\A\h{64}\z/

      attr_reader :bytes, :source

      def self.generate(source: "a new key") = new(SecureRandom.random_bytes(32), source:)

      # Parses 64 hex characters; whitespace around them is ignored.
      def self.parse(text, source:)
        hex = text.b.strip
        raise CredentialsError, "invalid key from #{source}: expected 64 hex characters" unless HEX.match?(hex)

        new([hex].pack("H*"), source:)
      end

      def initialize(bytes, source:)
        @bytes = bytes.b.freeze
        @source = source
        freeze
      end

      def hex = bytes.unpack1("H*")

      def inspect = "#<#{self.class.name} from #{source}>"

    end
  end
end
```

- [ ] **Step 8: Write `lib/metacrunch/credentials/box.rb`**

```ruby
# frozen_string_literal: true

require "openssl"

module Metacrunch
  module Credentials
    # File format v1: a header line and the strict Base64 of IV, tag and
    # ciphertext. AES-256-GCM with the header as authenticated data, so a
    # wrong key and every changed byte fail.
    module Box

      HEADER = "metacrunch credentials v1"
      HEADER_PREFIX = "metacrunch credentials "
      CIPHER = "aes-256-gcm"
      IV_LENGTH = 12
      TAG_LENGTH = 16

      module_function

      # The file content for plaintext, with a new random IV.
      def seal(plaintext, key)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key = key.bytes
        iv = cipher.random_iv
        cipher.auth_data = HEADER
        ciphertext = cipher.update(plaintext.b) + cipher.final
        "#{HEADER}\n#{[iv + cipher.auth_tag + ciphertext].pack("m0")}\n"
      end

      # The plaintext (UTF-8) in file content. path names the file in errors.
      def unseal(content, key, path:)
        raw = payload(content.b, path)
        cipher = OpenSSL::Cipher.new(CIPHER).decrypt
        cipher.key = key.bytes
        cipher.iv = raw.byteslice(0, IV_LENGTH)
        cipher.auth_tag = raw.byteslice(IV_LENGTH, TAG_LENGTH)
        cipher.auth_data = HEADER
        plaintext = cipher.update(raw.byteslice((IV_LENGTH + TAG_LENGTH)..)) + cipher.final
        plaintext.force_encoding(Encoding::UTF_8)
      rescue OpenSSL::Cipher::CipherError
        raise CredentialsError, "cannot decrypt #{path}: wrong key or modified file (key from #{key.source})"
      end

      # IV, tag and ciphertext as one binary String. CRLF line ends and
      # trailing blank lines are accepted.
      def payload(content, path)
        lines = content.lines(chomp: true)
        lines.pop while lines.last&.strip&.empty?
        header, body = lines
        check_header!(header, path)
        raw = lines.size == 2 ? body.strip.unpack1("m0") : ""
        raise not_credentials(path) if raw.bytesize < IV_LENGTH + TAG_LENGTH

        raw
      rescue ArgumentError
        raise not_credentials(path)
      end

      def check_header!(header, path)
        return if header == HEADER
        raise not_credentials(path) unless header&.start_with?(HEADER_PREFIX)

        raise CredentialsError, "unsupported credentials format in #{path}: #{header.delete_prefix(HEADER_PREFIX)}"
      end

      def not_credentials(path) = CredentialsError.new("not a metacrunch credentials file: #{path}")

    end
  end
end
```

- [ ] **Step 9: Require the new files**

In `lib/metacrunch.rb`, after `require_relative "metacrunch/params"`:

```ruby
require_relative "metacrunch/credentials"
require_relative "metacrunch/credentials/key"
require_relative "metacrunch/credentials/box"
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require_relative it }' test/unit/credentials_key_test.rb test/unit/credentials_box_test.rb test/unit/credentials_test.rb`
Expected: all tests pass, no warnings.

- [ ] **Step 11: Correct the layout line of the spec**

In the spec, section 6, replace the line

```
lib/metacrunch/credentials.rb            requires the parts below
```

with

```
lib/metacrunch/credentials.rb            the module: constants, file names, YAML, atomic writes
```

and add below the layout block:

```
`lib/metacrunch.rb` requires the parts; `lib/metacrunch/cli.rb` requires the
editor and the command, which only the CLI uses.
```

- [ ] **Step 12: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`
Expected: no offenses; all tests pass.

```bash
git add lib/metacrunch/errors.rb lib/metacrunch/credentials.rb lib/metacrunch/credentials lib/metacrunch.rb \
  test/unit/credentials_key_test.rb test/unit/credentials_box_test.rb test/unit/credentials_test.rb \
  docs/superpowers/specs/2026-10-11-metacrunch-ng-credentials-design.md
git commit -F - <<'EOF'
Add the encrypted credentials format

Keys are 32 random bytes in hex. A credentials file is a header line and
the Base64 of IV, tag and AES-256-GCM ciphertext; the plaintext is YAML
of plain types. Errors name files and key sources, never content.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 2: Finding directory, file and key

**Files:**
- Create: `lib/metacrunch/credentials/location.rb`
- Modify: `lib/metacrunch.rb` (require)
- Create: `test/support/credentials_helper.rb`
- Test: `test/unit/credentials_location_test.rb`

**Interfaces:**
- Consumes: `Credentials.environment`, `Credentials.present`, `Credentials.file_name`, `Credentials.key_name`, `Key.parse`, `Box.seal`, `Box.unseal` (Task 1).
- Produces:
  - `Credentials::Location.for_job(job_file:, env:, environment: nil, directory: nil) -> Location` (job_file: String or nil; env: Hash of variables)
  - `Credentials::Location.for_command(cwd:, env:, environment: nil, directory: nil) -> Location`
  - `Location#directory` (String or nil), `#environment` (String or nil), `#searched` (String or nil: what was searched without result), `#explicit?`, `#exist?`, `#file` (String or nil), `#key_file` (String or nil), `#key -> Key | nil`, `#key! -> Key` (raises `CredentialsError`)
  - Test helper `CredentialsHelper`: `in_tmpdir { |root| }`, `write_credentials(root, data, environment: nil, key: Key.generate, key_file: true) -> Key`, `write_file(root, relative, content) -> path`, `unseal(path, key) -> String`

- [ ] **Step 1: Write the test helper**

`test/support/credentials_helper.rb`:

```ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"

# Temporary projects with encrypted credentials.
module CredentialsHelper

  # Yields the real path of a new temporary directory (macOS links /var to
  # /private/var, and the credentials code resolves links).
  def in_tmpdir
    Dir.mktmpdir("metacrunch-test") { |dir| yield File.realpath(dir) }
  end

  # Writes ROOT/.metacrunch/credentials[.ENV].yml.enc with data (a Hash or
  # YAML text) and, with key_file: true, the key file. Returns the key.
  def write_credentials(root, data, environment: nil, key: Metacrunch::Credentials::Key.generate, key_file: true)
    dir = File.join(root, ".metacrunch")
    FileUtils.mkdir_p(dir)
    text = data.is_a?(String) ? data : YAML.dump(data)
    content = Metacrunch::Credentials::Box.seal(text, key)
    File.write(File.join(dir, Metacrunch::Credentials.file_name(environment)), content)
    File.write(File.join(dir, Metacrunch::Credentials.key_name(environment)), "#{key.hex}\n") if key_file
    key
  end

  # Writes a file below root, with its directories, and returns its path.
  def write_file(root, relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def unseal(path, key) = Metacrunch::Credentials::Box.unseal(File.binread(path), key, path:)

end
```

- [ ] **Step 2: Write the failing tests**

`test/unit/credentials_location_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsLocationTest < Minitest::Test

  include CredentialsHelper

  Location = Metacrunch::Credentials::Location

  def test_takes_the_nearest_metacrunch_directory_above_the_job_file
    in_tmpdir do |root|
      FileUtils.mkdir_p([File.join(root, ".metacrunch"), File.join(root, "app", ".metacrunch")])
      job = write_file(root, "app/jobs/x.rb", "")

      assert_equal File.join(root, "app", ".metacrunch"), Location.for_job(job_file: job, env: {}).directory
    end
  end

  def test_starts_in_the_directory_of_the_job_file
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "jobs", ".metacrunch"))
      job = write_file(root, "jobs/x.rb", "")

      assert_equal File.join(root, "jobs", ".metacrunch"), Location.for_job(job_file: job, env: {}).directory
    end
  end

  def test_resolves_a_symlinked_job_file
    in_tmpdir do |root|
      FileUtils.mkdir_p([File.join(root, "project", ".metacrunch"), File.join(root, "bin")])
      File.symlink(write_file(root, "project/jobs/x.rb", ""), File.join(root, "bin", "x"))

      assert_equal File.join(root, "project", ".metacrunch"),
                   Location.for_job(job_file: File.join(root, "bin", "x"), env: {}).directory
    end
  end

  def test_falls_back_to_the_home_directory
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "home", ".metacrunch"))
      job = write_file(root, "opt/jobs/x.rb", "")

      assert_equal File.join(root, "home", ".metacrunch"),
                   Location.for_job(job_file: job, env: {"HOME" => File.join(root, "home")}).directory
    end
  end

  def test_a_project_directory_without_the_environment_file_hides_the_home_directory
    in_tmpdir do |root|
      write_credentials(File.join(root, "home"), {"a" => 1}, environment: "production")
      FileUtils.mkdir_p(File.join(root, "opt", ".metacrunch"))
      job = write_file(root, "opt/jobs/x.rb", "")
      location = Location.for_job(job_file: job, env: {"HOME" => File.join(root, "home")}, environment: "production")

      assert_equal File.join(root, "opt", ".metacrunch", "credentials.production.yml.enc"), location.file
    end
  end

  def test_says_what_it_searched_when_there_is_no_directory
    in_tmpdir do |root|
      job = write_file(root, "jobs/x.rb", "")
      location = Location.for_job(job_file: job, env: {"HOME" => File.join(root, "home")})

      assert_nil location.directory
      assert_equal "no .metacrunch/ above #{job}, no ~/.metacrunch/", location.searched
    end
  end

  def test_works_without_home_and_without_job_file
    location = Location.for_job(job_file: nil, env: {})

    assert_nil location.directory
    assert_equal "no ~/.metacrunch/", location.searched
  end

  def test_the_option_wins_over_the_variable_and_the_search
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "jobs", ".metacrunch"))
      job = write_file(root, "jobs/x.rb", "")
      env = {"METACRUNCH_CREDENTIALS" => "/from/variable"}

      assert_equal "/from/option", Location.for_job(job_file: job, env:, directory: "/from/option").directory
      assert_equal "/from/variable", Location.for_job(job_file: job, env:).directory
      assert_predicate Location.for_job(job_file: job, env:), :explicit?
    end
  end

  def test_a_relative_directory_is_relative_to_the_working_directory
    in_tmpdir do |root|
      directory = Dir.chdir(root) { Location.for_job(job_file: nil, env: {}, directory: "secrets").directory }

      assert_equal File.join(root, "secrets"), directory
    end
  end

  def test_files_follow_the_environment
    location = Location.for_job(job_file: nil, env: {"METACRUNCH_ENV" => "production"}, directory: "/p/.metacrunch")

    assert_equal "/p/.metacrunch/credentials.production.yml.enc", location.file
    assert_equal "/p/.metacrunch/master.production.key", location.key_file
  end

  def test_the_key_comes_from_the_key_file
    in_tmpdir do |root|
      key = write_credentials(root, {})
      found = Location.for_job(job_file: nil, env: {}, directory: File.join(root, ".metacrunch")).key

      assert_equal [key.hex, File.join(root, ".metacrunch", "master.key")], [found.hex, found.source]
    end
  end

  def test_the_key_variable_wins_over_the_key_file
    in_tmpdir do |root|
      write_credentials(root, {})
      variable = Metacrunch::Credentials::Key.generate
      env = {"METACRUNCH_MASTER_KEY" => variable.hex}
      found = Location.for_job(job_file: nil, env:, directory: File.join(root, ".metacrunch")).key

      assert_equal [variable.hex, "METACRUNCH_MASTER_KEY"], [found.hex, found.source]
    end
  end

  def test_without_a_key_key_bang_says_how_to_provide_one
    location = Location.for_job(job_file: nil, env: {}, directory: "/p/.metacrunch", environment: "production")
    error = assert_raises(Metacrunch::CredentialsError) { location.key! }

    assert_nil location.key
    assert_equal "no key for /p/.metacrunch/credentials.production.yml.enc: set METACRUNCH_MASTER_KEY or " \
                 "create /p/.metacrunch/master.production.key", error.message
  end

  def test_the_command_searches_above_the_working_directory
    in_tmpdir do |root|
      FileUtils.mkdir_p([File.join(root, ".metacrunch"), File.join(root, "jobs")])
      location = Location.for_command(cwd: File.join(root, "jobs"), env: {})

      assert_equal File.join(root, ".metacrunch"), location.directory
      assert_predicate location, :exist?
    end
  end

  def test_the_command_never_picks_the_home_directory_by_itself
    in_tmpdir do |home|
      FileUtils.mkdir_p([File.join(home, ".metacrunch"), File.join(home, "new")])
      location = Location.for_command(cwd: File.join(home, "new"), env: {"HOME" => home})

      assert_equal File.join(home, "new", ".metacrunch"), location.directory
      refute_predicate location, :exist?
    end
  end

  def test_the_command_takes_the_home_directory_when_it_is_given
    in_tmpdir do |home|
      FileUtils.mkdir_p([File.join(home, ".metacrunch"), File.join(home, "new")])
      location = Location.for_command(cwd: File.join(home, "new"), env: {"HOME" => home},
                                      directory: File.join(home, ".metacrunch"))

      assert_equal File.join(home, ".metacrunch"), location.directory
    end
  end

end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/credentials_location_test.rb`
Expected: errors `uninitialized constant Metacrunch::Credentials::Location`.

- [ ] **Step 4: Write `lib/metacrunch/credentials/location.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Credentials
    # Where the credentials of one environment are: a directory, the file
    # and the key file in it. A run searches from its job file (for_job),
    # the credentials command from the working directory (for_command).
    class Location

      attr_reader :directory, :environment, :searched

      # --credentials DIR (directory:), else METACRUNCH_CREDENTIALS, else the
      # nearest .metacrunch/ at or above the job file (links resolved), else
      # ~/.metacrunch/. directory is nil if there is none.
      def self.for_job(job_file:, env:, environment: nil, directory: nil)
        environment = Credentials.environment(environment, env)
        explicit = explicit_directory(directory, env)
        return new(File.expand_path(explicit), environment:, env:, explicit: true) if explicit

        personal = personal_directory(env)
        found = job_file && upward(File.dirname(File.realpath(job_file)))
        found ||= personal if personal && File.directory?(personal)
        searched = [("no #{DIRECTORY}/ above #{job_file}" if job_file), "no ~/#{DIRECTORY}/"].compact.join(", ")
        new(found, environment:, env:, searched:)
      end

      # Like for_job, but from the working directory, and ~/.metacrunch/
      # only when it is given. Without a .metacrunch/ above cwd the
      # directory is cwd/.metacrunch, which edit creates.
      def self.for_command(cwd:, env:, environment: nil, directory: nil)
        environment = Credentials.environment(environment, env)
        explicit = explicit_directory(directory, env)
        return new(File.expand_path(explicit, cwd), environment:, env:, explicit: true) if explicit

        personal = personal_directory(env)
        personal = File.realpath(personal) if personal && File.directory?(personal)
        found = upward(File.realpath(cwd), skip: personal)
        new(found || File.join(cwd, DIRECTORY), environment:, env:, searched: "no #{DIRECTORY}/ above #{cwd}")
      end

      def self.explicit_directory(option, env)
        Credentials.present(option) || Credentials.present(env[DIRECTORY_VARIABLE])
      end

      def self.personal_directory(env)
        home = Credentials.present(env["HOME"])
        home && File.join(home, DIRECTORY)
      end

      # The nearest DIRECTORY at or above start, except skip.
      def self.upward(start, skip: nil)
        dir = start
        loop do
          candidate = File.join(dir, DIRECTORY)
          return candidate if candidate != skip && File.directory?(candidate)

          parent = File.dirname(dir)
          return if parent == dir

          dir = parent
        end
      end

      private_class_method :explicit_directory, :personal_directory, :upward

      def initialize(directory, environment:, env:, explicit: false, searched: nil)
        @directory = directory
        @environment = environment
        @env = env
        @explicit = explicit
        @searched = searched
      end

      def explicit? = @explicit

      def exist? = !directory.nil? && File.directory?(directory)

      def file = directory && File.join(directory, Credentials.file_name(environment))

      def key_file = directory && File.join(directory, Credentials.key_name(environment))

      # METACRUNCH_MASTER_KEY, else the key file; nil if there is neither.
      def key
        value = Credentials.present(@env[KEY_VARIABLE])
        return Key.parse(value, source: KEY_VARIABLE) if value
        return unless key_file && File.file?(key_file)

        Key.parse(File.read(key_file), source: key_file)
      end

      def key!
        key || raise(CredentialsError, "no key for #{file}: set #{KEY_VARIABLE} or create #{key_file}")
      end

    end
  end
end
```

- [ ] **Step 5: Require it**

In `lib/metacrunch.rb`, after `require_relative "metacrunch/credentials/box"`:

```ruby
require_relative "metacrunch/credentials/location"
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/credentials_location_test.rb`
Expected: all tests pass.

- [ ] **Step 7: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`

```bash
git add lib/metacrunch/credentials/location.rb lib/metacrunch.rb test/support/credentials_helper.rb \
  test/unit/credentials_location_test.rb
git commit -F - <<'EOF'
Find credentials above the job file, then in the home directory

The nearest .metacrunch/ at or above the job file decides alone;
~/.metacrunch/ is the fallback, and --credentials or
METACRUNCH_CREDENTIALS override both. The credentials command searches
from the working directory and never picks ~/.metacrunch/ by itself.
The key comes from METACRUNCH_MASTER_KEY, else from the key file.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 3: The lazy store

**Files:**
- Create: `lib/metacrunch/credentials/store.rb`
- Modify: `lib/metacrunch/credentials.rb` (`Credentials.store`)
- Modify: `lib/metacrunch.rb` (require)
- Test: `test/unit/credentials_store_test.rb`

**Interfaces:**
- Consumes: `Location` (Task 2), `Box.unseal`, `Credentials.load_yaml` (Task 1).
- Produces:
  - `Credentials::Store.new(location, logger: nil)`
  - `Store#dig(path) -> value | nil` (path like `"fis.api_key"`; reads and decrypts once, on the first call; raises `CredentialsError`)
  - `Store#origin(path) -> String` (`"credential fis.api_key in FILE"`)
  - `Store#missing(path) -> String` (why there is no value)
  - `Credentials.store(job_file:, env:, logger: nil, environment: nil, directory: nil) -> Store`

- [ ] **Step 1: Write the failing tests**

`test/unit/credentials_store_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsStoreTest < Minitest::Test

  include CredentialsHelper
  include Override

  def test_digs_through_nested_hashes
    in_tmpdir do |root|
      write_credentials(root, {"fis" => {"api_key" => "sk-123"}, "port" => 9200})
      credentials = store(root)

      assert_equal ["sk-123", 9200], [credentials.dig("fis.api_key"), credentials.dig("port")]
    end
  end

  def test_missing_keys_nil_values_and_scalars_on_the_way_give_nil
    in_tmpdir do |root|
      write_credentials(root, {"fis" => {"api_key" => nil}, "port" => 9200})
      credentials = store(root)

      assert_equal [nil, nil, nil],
                   [credentials.dig("fis.api_key"), credentials.dig("es.password"), credentials.dig("port.x")]
    end
  end

  def test_decrypts_once
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1, "b" => 2})
      calls = 0
      unseal = Metacrunch::Credentials::Box.method(:unseal)
      counting = lambda do |*args, **options|
        calls += 1
        unseal.call(*args, **options)
      end
      credentials = store(root)
      override(Metacrunch::Credentials::Box, :unseal, counting) { [credentials.dig("a"), credentials.dig("b")] }

      assert_equal 1, calls
    end
  end

  def test_reads_nothing_before_the_first_dig
    in_tmpdir do |root|
      write_file(root, ".metacrunch/credentials.yml.enc", "garbage")
      credentials = store(root)

      assert_raises(Metacrunch::CredentialsError) { credentials.dig("a") }
    end
  end

  def test_a_failed_read_is_not_taken_for_empty_credentials
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1}, key_file: false)
      credentials = store(root)

      assert_raises(Metacrunch::CredentialsError) { credentials.dig("a") }
      assert_raises(Metacrunch::CredentialsError) { credentials.dig("a") }
    end
  end

  def test_explains_why_a_value_is_missing
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1})
      dir = File.join(root, ".metacrunch")

      assert_equal "fis.api_key not in #{dir}/credentials.yml.enc", store(root).missing("fis.api_key")
      assert_equal "no credentials for environment production in #{dir}",
                   store(root, environment: "production").missing("a")
    end
  end

  def test_explains_a_missing_file_without_environment
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".metacrunch"))

      assert_equal "no credentials.yml.enc in #{File.join(root, ".metacrunch")}", store(root).missing("a")
    end
  end

  def test_without_a_directory_there_are_no_values
    credentials = Metacrunch::Credentials.store(job_file: nil, env: {})

    assert_nil credentials.dig("fis.api_key")
    assert_equal "no credentials directory: no ~/.metacrunch/", credentials.missing("fis.api_key")
  end

  def test_a_given_directory_must_exist
    credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: "/nonexistent/.metacrunch")
    error = assert_raises(Metacrunch::CredentialsError) { credentials.dig("a") }

    assert_equal "credentials directory not found: /nonexistent/.metacrunch", error.message
  end

  def test_logs_the_decrypted_file_at_debug_level
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1})
      io = StringIO.new
      store(root, logger: Logger.new(io, level: Logger::DEBUG)).dig("a")

      assert_includes io.string, "credentials: #{root}/.metacrunch/credentials.yml.enc"
    end
  end

  def test_origin_names_the_path_and_the_file
    assert_equal "credential fis.api_key in /p/.metacrunch/credentials.yml.enc",
                 Metacrunch::Credentials.store(job_file: nil, env: {}, directory: "/p/.metacrunch").origin("fis.api_key")
  end

  private

  def store(root, environment: nil, logger: nil)
    Metacrunch::Credentials.store(job_file: nil, env: {}, environment:, logger:,
                                  directory: File.join(root, ".metacrunch"))
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/credentials_store_test.rb`
Expected: errors `undefined method 'store' for module Metacrunch::Credentials`.

- [ ] **Step 3: Write `lib/metacrunch/credentials/store.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Credentials
    # The credentials of one Location, read and decrypted on the first dig,
    # once. Params asks it only for values that neither the command line nor
    # an env: variable gives.
    class Store

      def initialize(location, logger: nil)
        @location = location
        @logger = logger
        @loaded = false
        @data = nil
      end

      # The value at path ("fis.api_key"), or nil. Raises CredentialsError if
      # the credentials cannot be read.
      def dig(path)
        data = load
        data && path.split(".").reduce(data) { |node, key| node.is_a?(Hash) ? node[key] : nil }
      end

      # Where a value came from, for messages.
      def origin(path) = "credential #{path} in #{@location.file}"

      # Why path has no value, for the message about a missing parameter.
      def missing(path)
        location = @location
        return "no credentials directory: #{location.searched}" if location.directory.nil?

        unless File.file?(location.file)
          return "no credentials for environment #{location.environment} in #{location.directory}" if location.environment

          return "no #{File.basename(location.file)} in #{location.directory}"
        end
        "#{path} not in #{location.file}"
      end

      private

      def load
        return @data if @loaded

        @data = read
        @loaded = true
        @data
      end

      def read
        location = @location
        return if location.directory.nil?
        if location.explicit? && !location.exist?
          raise CredentialsError, "credentials directory not found: #{location.directory}"
        end
        return unless File.file?(location.file)

        plaintext = Box.unseal(File.binread(location.file), location.key!, path: location.file)
        @logger&.debug("credentials: #{location.file}")
        Credentials.load_yaml(plaintext, location.file)
      end

    end
  end
end
```

- [ ] **Step 4: Add `Credentials.store`**

In `lib/metacrunch/credentials.rb`, after `def present(value) = ...`:

```ruby

    # The store for a run: Location.for_job with the run's options.
    def store(job_file:, env:, logger: nil, environment: nil, directory: nil)
      Store.new(Location.for_job(job_file:, env:, environment:, directory:), logger:)
    end
```

- [ ] **Step 5: Require it**

In `lib/metacrunch.rb`, after `require_relative "metacrunch/credentials/location"`:

```ruby
require_relative "metacrunch/credentials/store"
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/credentials_store_test.rb`
Expected: all tests pass.

- [ ] **Step 7: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`

```bash
git add lib/metacrunch/credentials/store.rb lib/metacrunch/credentials.rb lib/metacrunch.rb \
  test/unit/credentials_store_test.rb
git commit -F - <<'EOF'
Read credentials lazily through a store

The store decrypts its file on the first dig and only once, explains why
a value is missing, and logs the decrypted file at debug level.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 4: Parameters with `credential:`

**Files:**
- Modify: `lib/metacrunch/params.rb`
- Test: `test/unit/params_credentials_test.rb`

**Interfaces:**
- Consumes: `Store#dig`, `#origin`, `#missing`, `Credentials.store` (Task 3); `CredentialsHelper` (Task 2).
- Produces:
  - `Params#param(name, type = String, default:, required:, env:, desc:, short:, credential: nil)`
  - `Params::Definition#credential` (String or nil), `#secret?`
  - `Params#bind_argv(argv, env: ENV, credentials: nil, warn: nil)` (credentials: a `Store` or nil; warn: a callable that takes a message)
  - Bound values: `inspect`, `to_s` and `pretty_print` show secret parameters as `[secret]`.

- [ ] **Step 1: Write the failing tests**

`test/unit/params_credentials_test.rb`:

```ruby
# frozen_string_literal: true

require "pp"
require "test_helper"

class ParamsCredentialsTest < Minitest::Test

  include CredentialsHelper

  SECRET = "sk-123-geheim"

  def test_the_command_line_wins_over_env_and_credentials
    with_credentials({"fis" => {"api_key" => "from-credentials"}}) do |credentials|
      params = api_key_schema
      env = {"FIS_API_KEY" => "from-env"}

      assert_equal "from-cli", params.bind_argv(["--api-key", "from-cli"], env:, credentials:).api_key
      assert_equal "from-env", params.bind_argv([], env:, credentials:).api_key
      assert_equal "from-credentials", params.bind_argv([], env: {"FIS_API_KEY" => ""}, credentials:).api_key
    end
  end

  def test_the_default_comes_last
    with_credentials({}) do |credentials|
      assert_equal "from-default", api_key_schema(default: "from-default").bind_argv([], env: {}, credentials:).api_key
    end
  end

  def test_converts_credential_values_like_command_line_values
    data = {"bulk" => "42", "port" => 9200, "dry" => "yes", "tls" => true, "hosts" => ["es1", "es2"]}
    with_credentials(data) do |credentials|
      params = schema do
        param :bulk, Integer, credential: "bulk"
        param :port, Integer, credential: "port"
        param :dry, :bool, credential: "dry"
        param :tls, :bool, credential: "tls"
        param :hosts, Array, credential: "hosts"
      end

      assert_equal({bulk: 42, port: 9200, dry: true, tls: true, hosts: ["es1", "es2"]},
                   params.bind_argv([], env: {}, credentials:).to_h)
    end
  end

  def test_asks_to_quote_values_that_yaml_did_not_read_as_strings
    with_credentials("pin: 0123\npassword: no\n") do |credentials, dir|
      messages = ["pin", "password"].map do |path|
        params = schema { param :value, String, credential: path }
        assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, credentials:) }.message
      end

      assert_equal "invalid value for --value from credential pin in #{dir}/credentials.yml.enc: (hidden) is not " \
                   "a String; quote it in the credentials file", messages.first
      assert_match(/\(hidden\) is not a String; quote it in the credentials file\z/, messages.last)
    end
  end

  def test_a_hash_is_no_value
    with_credentials({"fis" => {"api_key" => {"nested" => SECRET}}}) do |credentials|
      error = assert_raises(Metacrunch::ParamError) { api_key_schema.bind_argv([], env: {}, credentials:) }

      assert_match(/\(hidden\) is not a String/, error.message)
      refute_includes error.message, SECRET
    end
  end

  def test_a_missing_required_value_names_every_source
    with_credentials({"other" => 1}, environment: "production") do |credentials, dir|
      error = assert_raises(Metacrunch::ParamError) do
        api_key_schema(required: true).bind_argv([], env: {}, credentials:)
      end

      assert_equal "missing required parameter --api-key (FIS_API_KEY unset; fis.api_key not in " \
                   "#{dir}/credentials.production.yml.enc)", error.message
    end
  end

  def test_a_missing_environment_file_is_named
    with_credentials({"fis" => {"api_key" => SECRET}}) do |_credentials, dir|
      credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: dir, environment: "production")
      error = assert_raises(Metacrunch::ParamError) do
        api_key_schema(required: true).bind_argv([], env: {}, credentials:)
      end

      assert_equal "missing required parameter --api-key (FIS_API_KEY unset; no credentials for environment " \
                   "production in #{dir})", error.message
    end
  end

  def test_without_credentials_the_message_says_so
    params = schema { param :api_key, String, credential: "fis.api_key", required: true }
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}) }

    assert_equal "missing required parameter --api-key (fis.api_key: no credentials)", error.message
  end

  def test_a_missing_value_names_the_unset_variable
    params = schema { param :url, String, env: "ES_URL", required: true }
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}) }

    assert_equal "missing required parameter --url (ES_URL unset)", error.message
  end

  def test_a_credential_path_needs_non_empty_segments
    errors = ["", ".a", "a.", "a..b", :a].map do |path|
      assert_raises(ArgumentError) { schema { param :x, String, credential: path } }.message
    end

    assert_equal "parameter x: credential must be a path like \"fis.api_key\", got \"\"", errors.first
    assert_equal 5, errors.grep(/credential must be a path/).size
  end

  def test_help_shows_the_sources_of_a_secret_but_no_value
    help = api_key_schema(required: true, desc: "FIS API key").help

    assert_includes help, "FIS API key (required, secret, env: FIS_API_KEY, credential: fis.api_key)"
  end

  def test_help_hides_the_default_of_a_secret
    help = api_key_schema(default: SECRET).help

    refute_includes help, SECRET
    assert_includes help, "(secret, env: FIS_API_KEY, credential: fis.api_key)"
  end

  def test_invalid_values_of_a_secret_are_hidden_from_every_source
    with_credentials({"pin" => SECRET}) do |credentials|
      params = schema { param :pin, Integer, env: "PIN", credential: "pin" }
      messages = [[["--pin", SECRET], {}], [[], {"PIN" => SECRET}], [[], {}]].map do |argv, env|
        assert_raises(Metacrunch::ParamError) { params.bind_argv(argv, env:, credentials:) }.message
      end

      assert(messages.all? { it.include?("(hidden) is not an Integer") }, messages.inspect)
      refute(messages.any? { it.include?(SECRET) }, messages.inspect)
    end
  end

  def test_an_invalid_default_of_a_secret_is_hidden
    error = assert_raises(ArgumentError) { schema { param :pin, Integer, credential: "pin", default: SECRET } }

    assert_equal "invalid default for parameter pin: (hidden) is not an Integer", error.message
  end

  def test_inspect_to_s_and_pp_show_secrets_as_secret
    params = schema do
      param :index, String
      param :api_key, String, credential: "fis.api_key"
    end
    values = params.bind_hash(index: "test", api_key: SECRET)

    assert_equal "#<data index=\"test\", api_key=[secret]>", values.inspect
    assert_equal values.inspect, values.to_s
    assert_equal "#<data index=\"test\", api_key=[secret]>\n", values.pretty_inspect
  end

  def test_the_values_keep_the_secret
    values = api_key_schema.bind_hash(api_key: SECRET)

    assert_equal [SECRET, {api_key: SECRET}], [values.api_key, values.to_h]
  end

  def test_warns_about_a_secret_on_the_command_line
    warnings = []
    api_key_schema.bind_argv(["--api-key", SECRET], env: {}, warn: ->(message) { warnings << message })

    assert_equal ["--api-key is a secret; pass it by FIS_API_KEY or credentials instead"], warnings
  end

  def test_without_env_the_warning_names_only_the_credentials
    warnings = []
    params = schema { param :api_key, String, credential: "fis.api_key" }
    params.bind_argv(["--api-key", SECRET], env: {}, warn: ->(message) { warnings << message })

    assert_equal ["--api-key is a secret; pass it by credentials instead"], warnings
  end

  def test_no_warning_for_other_parameters_and_for_values_from_env
    warnings = []
    params = schema do
      param :index, String
      param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key"
    end
    params.bind_argv(["--index", "x"], env: {"FIS_API_KEY" => SECRET}, warn: ->(message) { warnings << message })

    assert_empty warnings
  end

  def test_credentials_are_read_only_when_command_line_and_env_give_no_value
    in_tmpdir do |root|
      write_file(root, ".metacrunch/credentials.yml.enc", "garbage")
      credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: File.join(root, ".metacrunch"))
      params = api_key_schema

      assert_equal "cli", params.bind_argv(["--api-key", "cli"], env: {}, credentials:).api_key
      assert_equal "env", params.bind_argv([], env: {"FIS_API_KEY" => "env"}, credentials:).api_key
      assert_raises(Metacrunch::CredentialsError) { params.bind_argv([], env: {}, credentials:) }
    end
  end

  def test_bind_hash_ignores_credentials
    assert_nil api_key_schema.bind_hash({}).api_key
  end

  private

  def schema(&) = Metacrunch::Params.new.tap { |params| params.instance_exec(&) }

  def api_key_schema(**options)
    schema { param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key", **options }
  end

  # Yields a store over credentials with data (a Hash or YAML text), and
  # the credentials directory.
  def with_credentials(data, environment: nil)
    in_tmpdir do |root|
      write_credentials(root, data, environment:)
      dir = File.join(root, ".metacrunch")
      yield Metacrunch::Credentials.store(job_file: nil, env: {}, directory: dir, environment:), dir
    end
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/params_credentials_test.rb`
Expected: errors `unknown keyword: :credential` and `unknown keyword: :credentials`.

- [ ] **Step 3: Extend the definition and the declaration**

In `lib/metacrunch/params.rb`:

Replace the `Definition` declaration with:

```ruby
    Definition = Data.define(:name, :type, :default, :required, :env, :desc, :short, :credential) do
      def option = "--#{name.to_s.tr("_", "-")}"

      # A parameter with credential: is secret: its value is hidden in
      # help texts, error messages and inspect.
      def secret? = !credential.nil?
    end
```

Add these constants after `TYPE_NAMES`:

```ruby

    CREDENTIAL_PATH = /\A[^.]+(\.[^.]+)*\z/
    HIDDEN = "(hidden)"
    QUOTE_HINT = "quote it in the credentials file"

    # Shows secret parameters as [secret] in inspect, to_s and pp. The
    # values class defines SECRETS.
    module Redacted

      def inspect
        fields = to_h.map do |name, value|
          "#{name}=#{self.class::SECRETS.include?(name) ? "[secret]" : value.inspect}"
        end
        "#<data #{fields.join(", ")}>"
      end

      def to_s = inspect

      def pretty_print(printer) = printer.text(inspect)

    end
```

Replace `param` with:

```ruby
    # Defaults are converted and checked like CLI values when the parameter
    # is declared, so a wrong default fails early. credential: a path in
    # the credentials ("fis.api_key"); it makes the parameter secret.
    def param(name, type = String, default: nil, required: false, env: nil, desc: nil, short: nil, credential: nil)
      name = check_name!(name)
      raise ArgumentError, "unsupported type #{type.inspect} for parameter #{name}" unless TYPES.include?(type)
      raise ArgumentError, "parameter #{name}: #{RESERVED_SHORT} is reserved for help" if short == RESERVED_SHORT
      raise ArgumentError, "parameter #{name}: use either default: or required: true" if required && !default.nil?

      check_credential!(name, credential)
      definition = Definition.new(name:, type:, default: nil, required:, env:, desc:, short:, credential:)
      @definitions[name] = definition.with(default: default_value(definition, default))
      nil
    end
```

- [ ] **Step 4: Bind with credentials and warnings**

Replace `bind_argv` with:

```ruby
    # Binds CLI arguments. A parameter without a value on the command line
    # is read from its env: variable (empty counts as unset), then from the
    # credentials (a Credentials::Store, asked only now), then the default.
    # warn is called with a message for a secret given on the command line.
    def bind_argv(argv, env: ENV, credentials: nil, warn: nil)
      given = {}
      positional = option_parser(given).parse(argv)
      values = @definitions.to_h do |name, definition|
        [name, bind(definition, given, env, credentials, warn)]
      end
      build(values, positional)
    rescue OptionParser::ParseError => e
      raise ParamError, e.message
    end
```

In the private section, replace `resolve`, `convert` and `invalid!` with the following, and add `bind`, `sources`, `secret_warning` and `check_credential!`:

```ruby
    def check_credential!(name, path)
      return if path.nil? || (path.is_a?(String) && CREDENTIAL_PATH.match?(path))

      raise ArgumentError, "parameter #{name}: credential must be a path like \"fis.api_key\", got #{path.inspect}"
    end

    def bind(definition, given, env, credentials, warn)
      if given.key?(definition.name)
        warn&.call(secret_warning(definition)) if definition.secret?
        return resolve(definition, given[definition.name])
      end

      raw = env_value(definition, env)
      return resolve(definition, raw, origin: "environment variable #{definition.env}") unless raw.nil?

      raw = credentials&.dig(definition.credential) if definition.credential
      unless raw.nil?
        return resolve(definition, raw, origin: credentials.origin(definition.credential), hint: QUOTE_HINT)
      end

      resolve(definition, nil, sources: -> { sources(definition, credentials) })
    end

    # What was tried for a missing value, e.g. "FIS_API_KEY unset;
    # fis.api_key not in FILE"; nil for a parameter without env: and
    # credential:.
    def sources(definition, credentials)
      tried = []
      tried << "#{definition.env} unset" if definition.env
      if definition.credential
        tried << (credentials ? credentials.missing(definition.credential) : "#{definition.credential}: no credentials")
      end
      tried.join("; ") unless tried.empty?
    end

    def secret_warning(definition)
      by = definition.env ? "#{definition.env} or credentials" : "credentials"
      "#{definition.option} is a secret; pass it by #{by} instead"
    end

    def resolve(definition, raw, origin: nil, hint: nil, sources: nil)
      value = raw.nil? ? definition.default : frozen_copy(convert(definition, raw, origin:, hint:))
      return value unless definition.required && value.nil?

      detail = sources&.call
      raise ParamError, "missing required parameter #{definition.option}#{" (#{detail})" if detail}"
    end

    def convert(definition, raw, origin: nil, hint: nil)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      value = value.to_f if definition.type == Float && value.is_a?(Integer)
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw, origin, hint)
    rescue ArgumentError, TypeError
      invalid!(definition, raw, origin, hint)
    end

    # The hint applies to values that YAML did not read as Strings (no,
    # 0123) where a String is expected.
    def invalid!(definition, raw, origin, hint = nil)
      expected = TYPE_NAMES.fetch(definition.type)
      from = origin ? " from #{origin}" : ""
      shown = definition.secret? ? HIDDEN : raw.inspect
      note = hint && definition.type == String && !raw.is_a?(String) ? "; #{hint}" : ""
      raise ParamError, "invalid value for #{definition.option}#{from}: #{shown} is not #{expected}#{note}"
    end
```

- [ ] **Step 5: Redact help, defaults and inspect**

Replace `default_value` with:

```ruby
    def default_value(definition, default)
      return if default.nil?

      frozen_copy(convert(definition, default))
    rescue ParamError
      expected = TYPE_NAMES.fetch(definition.type)
      shown = definition.secret? ? HIDDEN : default.inspect
      raise ArgumentError, "invalid default for parameter #{definition.name}: #{shown} is not #{expected}"
    end
```

Replace `description` with:

```ruby
    def description(definition)
      notes = []
      notes << "required" if definition.required
      notes << "secret" if definition.secret?
      notes << "default: #{definition.default}" unless definition.default.nil? || definition.secret?
      notes << "env: #{definition.env}" if definition.env
      notes << "credential: #{definition.credential}" if definition.credential
      text = [definition.desc, ("(#{notes.join(", ")})" if notes.any?)].compact.join(" ")
      text unless text.empty?
    end
```

Replace `values_class` with:

```ruby
    def values_class
      @values_class ||= begin
        klass = Data.define(*@definitions.keys, *[@args_definition&.name].compact)
        secrets = @definitions.values.select(&:secret?).map(&:name)
        if secrets.any?
          klass.const_set(:SECRETS, secrets.freeze)
          klass.include(Redacted)
        end
        klass
      end
    end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require_relative it }' test/unit/params_credentials_test.rb test/unit/params_test.rb`
Expected: all tests pass (`params_test.rb` matches messages with regexps, so the new "(X unset)" suffix does not break it).

- [ ] **Step 7: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`

```bash
git add lib/metacrunch/params.rb test/unit/params_credentials_test.rb
git commit -F - <<'EOF'
Read parameters from credentials and keep secrets out of output

A parameter with credential: gets its value from the command line, its
env: variable, the credentials (asked only then) or its default. It is
secret: help texts, error messages, inspect and pp hide its value, and
a value on the command line gives a warning. A missing value names
every source that was tried.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 5: Credentials in runs: `Job#run`, `run`, `check` and `trace`

**Files:**
- Modify: `lib/metacrunch/job.rb`
- Modify: `lib/metacrunch/loader.rb`
- Modify: `lib/metacrunch/cli/command.rb`
- Modify: `lib/metacrunch/cli/job_command.rb`
- Modify: `test/support/credentials_helper.rb` (`SECRET`, `SECRET_JOB`)
- Test: `test/unit/job_credentials_test.rb`, `test/cli/credentials_options_test.rb`

**Interfaces:**
- Consumes: `Credentials.store` (Task 3), `Params#bind_argv(argv, env:, credentials:, warn:)` (Task 4).
- Produces:
  - `Job#file` (String or nil), set by the loader
  - `Cli::Command#parse(parser, argv)` (private hook, default `parser.order!(argv)`)
  - `Cli::Command#credentials_options(parser, *directory_help)` (private; sets `@environment` and `@credentials`)
  - Test helper: `CredentialsHelper::SECRET`, `CredentialsHelper::SECRET_JOB` (a job file text)

- [ ] **Step 1: Add the secret job to the test helper**

In `test/support/credentials_helper.rb`, after `module CredentialsHelper`:

```ruby

  SECRET = "sk-123-geheim"

  # A job that needs a secret and writes it reversed, so tests can check the
  # value without the secret itself appearing in the output.
  SECRET_JOB = <<~RUBY
    # frozen_string_literal: true

    Metacrunch.job do
      params do
        param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key", required: true
        param :output, String, default: "-"
      end

      source [1, 2]
      map { params.api_key.reverse }
      sink Metacrunch::JsonLines::Writer.new(params.output)
    end
  RUBY
```

- [ ] **Step 2: Write the failing library tests**

`test/unit/job_credentials_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class JobCredentialsTest < Minitest::Test

  include CredentialsHelper

  def test_load_job_remembers_the_file
    in_tmpdir do |root|
      path = write_file(root, "jobs/x.rb", SECRET_JOB)

      assert_equal path, Metacrunch.load_job(path).file
      assert_nil Metacrunch::Job.new { source [] }.file
    end
  end

  def test_run_reads_credentials_above_the_job_file
    in_tmpdir do |root|
      write_credentials(root, {"fis" => {"api_key" => SECRET}}, environment: "production")
      job = Metacrunch.load_job(write_file(root, "jobs/x.rb", SECRET_JOB))
      output = File.join(root, "out.jsonl")
      result = job.run(["--output", output], env: {"METACRUNCH_ENV" => "production"}, logger: Logger.new(nil))

      assert_equal :ok, result.status
      assert_equal "\"#{SECRET.reverse}\"\n" * 2, File.read(output)
    end
  end

  def test_run_takes_the_key_from_the_environment
    in_tmpdir do |root|
      key = write_credentials(root, {"fis" => {"api_key" => SECRET}}, key_file: false)
      job = Metacrunch.load_job(write_file(root, "jobs/x.rb", SECRET_JOB))
      output = File.join(root, "out.jsonl")
      job.run(["--output", output], env: {"METACRUNCH_MASTER_KEY" => key.hex}, logger: Logger.new(nil))

      assert_equal "\"#{SECRET.reverse}\"\n" * 2, File.read(output)
    end
  end

  def test_run_logs_a_warning_for_a_secret_on_the_command_line
    in_tmpdir do |root|
      job = Metacrunch.load_job(write_file(root, "jobs/x.rb", SECRET_JOB))
      io = StringIO.new
      job.run(["--api-key", SECRET, "--output", File.join(root, "out.jsonl")], env: {}, logger: Logger.new(io))

      assert_includes io.string, "--api-key is a secret; pass it by FIS_API_KEY or credentials instead"
      refute_includes io.string, SECRET
    end
  end

  def test_run_rejects_an_invalid_environment_name
    job = Metacrunch::Job.new { source [] }

    assert_raises(Metacrunch::CredentialsError) do
      job.run([], env: {"METACRUNCH_ENV" => "Prod"}, logger: Logger.new(nil))
    end
  end

end
```

- [ ] **Step 3: Write the failing CLI tests**

`test/cli/credentials_options_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsOptionsTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  def test_run_gets_the_value_of_the_environment_given_by_option
    in_tmpdir do |root|
      job_file = project(root, environment: "production")
      code, stdout, stderr = cli("run", "-e", "production", job_file)

      assert_equal [0, "\"#{SECRET.reverse}\"\n" * 2], [code, stdout], stderr
      refute_includes stderr, SECRET
    end
  end

  def test_the_credentials_option_names_the_directory
    in_tmpdir do |root|
      write_credentials(File.join(root, "vault"), {"fis" => {"api_key" => SECRET}})
      job_file = write_file(root, "jobs/secret.rb", SECRET_JOB)
      code, stdout, = cli("run", "--credentials", File.join(root, "vault", ".metacrunch"), job_file)

      assert_equal [0, "\"#{SECRET.reverse}\"\n" * 2], [code, stdout]
    end
  end

  def test_an_invalid_environment_name_is_a_usage_error
    in_tmpdir do |root|
      code, _stdout, stderr = cli("run", "-e", "Production", project(root))

      assert_equal 2, code
      assert_includes stderr, "invalid environment \"Production\""
    end
  end

  def test_a_wrong_key_is_a_usage_error_that_names_the_file
    in_tmpdir do |root|
      env = {"METACRUNCH_MASTER_KEY" => Metacrunch::Credentials::Key.generate.hex}
      code, _stdout, stderr = cli("run", project(root), env:)

      assert_equal 2, code
      assert_includes stderr, "cannot decrypt #{root}/.metacrunch/credentials.yml.enc: wrong key or modified file " \
                              "(key from METACRUNCH_MASTER_KEY)"
    end
  end

  def test_check_verifies_key_and_file
    in_tmpdir do |root|
      job_file = project(root)
      env = {"METACRUNCH_MASTER_KEY" => Metacrunch::Credentials::Key.generate.hex}

      assert_equal 0, cli("check", job_file).first
      assert_equal 2, cli("check", job_file, env:).first
    end
  end

  def test_verbose_logs_the_decrypted_file
    in_tmpdir do |root|
      _code, _stdout, stderr = cli("run", "-v", project(root))

      assert_includes stderr, "credentials: #{root}/.metacrunch/credentials.yml.enc"
      refute_includes stderr, SECRET
    end
  end

  def test_trace_gets_the_value
    in_tmpdir do |root|
      code, stdout, = cli("trace", "-n", "1", project(root))

      assert_equal 0, code
      assert_includes stdout, SECRET.reverse
    end
  end

  def test_run_help_lists_the_credentials_options
    stdout = cli("run", "--help")[1]

    assert_match(/-e, --environment NAME/, stdout)
    assert_match(/--credentials DIR/, stdout)
  end

  private

  # A project with credentials and the secret job; returns the job file.
  def project(root, environment: nil)
    write_credentials(root, {"fis" => {"api_key" => SECRET}}, environment:)
    write_file(root, "jobs/secret.rb", SECRET_JOB)
  end

end
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require_relative it }' test/unit/job_credentials_test.rb test/cli/credentials_options_test.rb`
Expected: failures (`undefined method 'file'`, `invalid option: -e`, missing required parameter).

- [ ] **Step 5: `Job#file` and `Job#run`**

In `lib/metacrunch/job.rb`, replace `attr_reader :name` with:

```ruby
    attr_reader :name

    # The file the job was loaded from (Metacrunch.load_job), else nil.
    # Credentials are searched from there.
    attr_accessor :file
```

Replace `run` with:

```ruby
    # Runs the job with CLI-style arguments. Raises ParamError for invalid
    # arguments (CredentialsError, a ParamError, for unreadable credentials)
    # and lets errors from the recipe itself (e.g. a component constructor
    # or a DSL mistake) propagate. Errors while the pipeline runs end up in
    # the Result. limit stops after that many records; workers runs the
    # steps in that many processes. Credentials follow env:
    # METACRUNCH_ENV, METACRUNCH_CREDENTIALS, METACRUNCH_MASTER_KEY, HOME.
    def run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil, limit: nil, workers: nil)
      credentials = Credentials.store(job_file: file, env:, logger:)
      warn = ->(message) { logger.warn(message) }
      built = pipeline(binder: ->(schema) { schema.bind_argv(argv, env:, credentials:, warn:) }, logger:)
      Engine.new(built.with(limit:), observer:, executor: Executor.for(workers)).run
    end
```

- [ ] **Step 6: The loader sets the file**

In `lib/metacrunch/loader.rb`, in `collect`, replace

```ruby
      Kernel.load(File.expand_path(path))
      jobs
```

with

```ruby
      Kernel.load(File.expand_path(path))
      jobs.each { it.file = File.expand_path(path) }
```

- [ ] **Step 7: Command hooks for parsing and the credentials options**

In `lib/metacrunch/cli/command.rb`, in `run`, replace `parser.order!(argv)` with `parse(parser, argv)`, and add in the private section after `def define_options(_parser) = nil`:

```ruby

      # Options end at the first argument that is not an option.
      def parse(parser, argv) = parser.order!(argv)

      # -e and --credentials, for the commands that read credentials.
      # directory_help: the description lines of --credentials.
      def credentials_options(parser, *directory_help)
        parser.on("-e", "--environment NAME", "Credentials environment (default: METACRUNCH_ENV)") do |name|
          @environment = name
        end
        parser.on("--credentials DIR", *directory_help) { @credentials = it }
      end
```

- [ ] **Step 8: `JobCommand` builds the store**

In `lib/metacrunch/cli/job_command.rb`, in `define_options`, after the `-v` line:

```ruby
        credentials_options(parser, "Credentials directory (default: METACRUNCH_CREDENTIALS,",
                            "then .metacrunch/ above the job file, then ~/.metacrunch/)")
```

Replace `build_pipeline` with:

```ruby
      # Evaluates the recipe with the job's arguments. Credentials are read
      # only if a parameter needs them.
      def build_pipeline(job, argv)
        credentials = Credentials.store(job_file: job.file, env: @env, logger:, environment: @environment,
                                        directory: @credentials)
        warn = ->(message) { logger.warn(message) }
        job.pipeline(binder: ->(schema) { schema.bind_argv(argv, env: @env, credentials:, warn:) }, logger:)
      end
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require_relative it }' test/unit/job_credentials_test.rb test/cli/credentials_options_test.rb`
Expected: all tests pass.

- [ ] **Step 10: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`

```bash
git add lib/metacrunch/job.rb lib/metacrunch/loader.rb lib/metacrunch/cli/command.rb \
  lib/metacrunch/cli/job_command.rb test/support/credentials_helper.rb test/unit/job_credentials_test.rb \
  test/cli/credentials_options_test.rb
git commit -F - <<'EOF'
Give runs credentials: -e, --credentials and Job#run

run, check and trace take -e/--environment and --credentials and
search credentials from the job file, which the loader now remembers in
Job#file. Job#run reads the same settings from its env. Secrets on the
command line are warned about through the logger.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 6: The `credentials` command and `show`

**Files:**
- Create: `lib/metacrunch/cli/credentials.rb`
- Modify: `lib/metacrunch/cli.rb`
- Test: `test/cli/credentials_command_test.rb`

**Interfaces:**
- Consumes: `Location.for_command` (Task 2), `Box.unseal` (Task 1), `Command#parse`, `#credentials_options` (Task 5).
- Produces:
  - `Cli::CredentialsCommand` with private `show_credentials(location)`, `existing_file(location) -> path`, `unseal(location, key = location.key!) -> String`, `display(path) -> String`, and dispatch in `execute`; Tasks 7 and 8 add `edit_credentials` and `rotate_credentials`.
  - `metacrunch credentials` in `Cli::COMMANDS`.

- [ ] **Step 1: Write the failing tests**

`test/cli/credentials_command_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsCommandTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  def test_show_prints_the_plaintext_and_names_the_file
    in_tmpdir do |root|
      write_credentials(root, "fis:\n  api_key: geheim\n")
      code, stdout, stderr = Dir.chdir(root) { cli("credentials", "show") }

      assert_equal [0, "fis:\n  api_key: geheim\n"], [code, stdout]
      assert_equal "Showing .metacrunch/credentials.yml.enc\n", stderr
    end
  end

  def test_options_may_stand_before_or_after_the_subcommand
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n", environment: "production")
      after = Dir.chdir(root) { cli("credentials", "show", "-e", "production") }
      before = Dir.chdir(root) { cli("credentials", "-e", "production", "show") }

      assert_equal [0, "a: 1\n"], after.take(2)
      assert_equal after, before
    end
  end

  def test_show_searches_above_the_working_directory
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      FileUtils.mkdir_p(File.join(root, "jobs"))
      code, stdout, stderr = Dir.chdir(File.join(root, "jobs")) { cli("credentials", "show") }

      assert_equal [0, "a: 1\n"], [code, stdout]
      assert_equal "Showing #{root}/.metacrunch/credentials.yml.enc\n", stderr
    end
  end

  def test_show_without_a_directory_fails
    in_tmpdir do |root|
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "show") }

      assert_equal 2, code
      assert_includes stderr, "no .metacrunch/ found above #{root}; use --credentials"
    end
  end

  def test_show_without_the_file_fails
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "show", "-e", "production") }

      assert_equal 2, code
      assert_includes stderr, "no credentials file #{root}/.metacrunch/credentials.production.yml.enc"
    end
  end

  def test_show_with_a_missing_given_directory_fails
    in_tmpdir do |root|
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "show", "--credentials", "vault") }

      assert_equal 2, code
      assert_includes stderr, "credentials directory not found: #{root}/vault"
    end
  end

  def test_missing_unknown_and_extra_subcommands_are_usage_errors
    assert_equal [2, 2, 2], [cli("credentials").first, cli("credentials", "list").first,
                             cli("credentials", "show", "extra").first]
    assert_includes cli("credentials", "list")[2], "unknown subcommand list"
  end

  def test_the_usage_lists_the_command
    assert_match(/^  credentials +Edit, show or rotate encrypted credentials$/, cli("--help")[1])
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/credentials_command_test.rb`
Expected: failures (`unknown command or job file: credentials`).

- [ ] **Step 3: Write `lib/metacrunch/cli/credentials.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch credentials edit|show|rotate: the encrypted credentials of
    # the project in the working directory (see Credentials::Location).
    class CredentialsCommand < Command

      NAME = "credentials"
      SUMMARY = "Edit, show or rotate encrypted credentials"
      USAGE = "credentials edit|show|rotate [-e ENV] [--credentials DIR]"
      SUBCOMMANDS = ["edit", "show", "rotate"].freeze

      private

      def define_options(parser)
        credentials_options(parser, "Credentials directory (default: METACRUNCH_CREDENTIALS,",
                            "then .metacrunch/ above the working directory)")
      end

      # Options may stand before or after the subcommand.
      def parse(parser, argv) = parser.permute!(argv)

      def execute(argv)
        subcommand = argv.shift
        raise UsageError, "no subcommand given (edit, show or rotate)" unless subcommand
        raise UsageError, "unknown subcommand #{subcommand}" unless SUBCOMMANDS.include?(subcommand)
        raise UsageError, "unexpected arguments: #{argv.join(" ")}" if argv.any?

        location = Credentials::Location.for_command(cwd: Dir.pwd, env: @env, environment: @environment,
                                                     directory: @credentials)
        case subcommand
        when "show" then show_credentials(location)
        end
      end

      def show_credentials(location)
        file = existing_file(location)
        @stderr.puts("Showing #{display(file)}")
        @stdout.puts(unseal(location))
        EXIT_CODES[:ok]
      end

      # The credentials file of location; raises if it or its directory is
      # missing.
      def existing_file(location)
        unless location.exist?
          raise CredentialsError, "credentials directory not found: #{location.directory}" if location.explicit?

          raise CredentialsError, "no #{Credentials::DIRECTORY}/ found above #{Dir.pwd}; use --credentials"
        end
        file = location.file
        raise CredentialsError, "no credentials file #{file}" unless File.file?(file)

        file
      end

      def unseal(location, key = location.key!)
        Credentials::Box.unseal(File.binread(location.file), key, path: location.file)
      end

      # path relative to the working directory if it is below it.
      def display(path)
        cwd = "#{Dir.pwd}/"
        path.start_with?(cwd) ? path.delete_prefix(cwd) : path
      end

    end
  end
end
```

- [ ] **Step 4: Register the command**

In `lib/metacrunch/cli.rb`:

- after `require_relative "cli/new"` add `require_relative "cli/credentials"`;
- replace the `COMMANDS` line with

  ```ruby
      COMMANDS = {
        "run" => RunCommand, "check" => CheckCommand, "trace" => TraceCommand, "new" => NewCommand,
        "credentials" => CredentialsCommand
      }.freeze
  ```

- replace `usage` with (the names are aligned to the longest one, now `credentials`):

  ```ruby
      def usage
        width = [*COMMANDS.keys, "help"].map(&:size).max
        commands = COMMANDS.map { |name, command| "  #{name.ljust(width)} #{command::SUMMARY}" }
        commands << "  #{"help".ljust(width)} Show the help of a command"
        <<~TEXT
          Usage: metacrunch COMMAND [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]
                 metacrunch JOB_FILE [JOB_PARAMS...] [ARGS...]    (same as run)

          Commands:
          #{commands.join("\n")}

          Options:
            -h, --help     Show this help
                --version  Show the version
        TEXT
      end
  ```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require_relative it }' test/cli/credentials_command_test.rb test/cli/cli_test.rb`
Expected: all tests pass.

- [ ] **Step 6: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`

```bash
git add lib/metacrunch/cli/credentials.rb lib/metacrunch/cli.rb test/cli/credentials_command_test.rb
git commit -F - <<'EOF'
Add metacrunch credentials show

The credentials command finds .metacrunch/ above the working directory,
or takes --credentials, and show prints the decrypted YAML. Options may
stand before or after the subcommand.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 7: `credentials edit`

**Files:**
- Create: `lib/metacrunch/credentials/editor.rb`
- Modify: `lib/metacrunch/cli.rb` (require the editor)
- Modify: `lib/metacrunch/cli/credentials.rb`
- Modify: `test/support/credentials_helper.rb` (scripted editor)
- Test: `test/cli/credentials_edit_test.rb`

**Interfaces:**
- Consumes: `Credentials.load_yaml`, `Credentials.write`, `Box.seal`, `Key.generate` (Task 1), `Location#key`, `#key!`, `#key_file` (Task 2), `CredentialsCommand#unseal`, `#display` (Task 6).
- Produces:
  - `Credentials::EditAborted < Metacrunch::Error`
  - `Credentials::Editor.new(env:, stdin:, stderr:)`, `#edit(text, name:) { |edited| check } -> String` (raises `EditAborted`, `CredentialsError` without editor)
  - `CredentialsCommand#edit_credentials(location)`, `#create_key(location) -> Key`
  - Test helper: `scripted_editor(root, *contents, status: 0) -> command String`, `editor_calls(root) -> Array of Hashes ("path", "mode", "dir_mode", "before")`

- [ ] **Step 1: Add the scripted editor to the test helper**

In `test/support/credentials_helper.rb`, add `require "json"`, `require "rbconfig"` and `require "shellwords"` to the requires, and in the module:

```ruby

  # The editor script: logs every call to calls.jsonl (path, modes, the
  # text it found), writes contents[n] on the n-th call (keeps the text if
  # there is none) and exits with the status in its directory.
  EDITOR_SCRIPT = <<~'RUBY'
    # frozen_string_literal: true

    require "json"

    path = ARGV.fetch(0)
    log = File.join(__dir__, "calls.jsonl")
    calls = File.exist?(log) ? File.readlines(log).size : 0
    File.open(log, "a") do |file|
      file.puts(JSON.generate("path" => path, "mode" => File.stat(path).mode & 0o777,
                              "dir_mode" => File.stat(File.dirname(path)).mode & 0o777, "before" => File.read(path)))
    end
    contents = JSON.parse(File.read(File.join(__dir__, "contents.json")))
    File.write(path, contents[calls]) if contents[calls]
    exit Integer(File.read(File.join(__dir__, "status")))
  RUBY

  # An EDITOR command that writes contents[n] on its n-th call and ends with
  # status. Its files live in ROOT/editor.
  def scripted_editor(root, *contents, status: 0)
    dir = File.join(root, "editor")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "editor.rb"), EDITOR_SCRIPT)
    File.write(File.join(dir, "contents.json"), JSON.generate(contents))
    File.write(File.join(dir, "status"), status.to_s)
    Shellwords.join([RbConfig.ruby, File.join(dir, "editor.rb")])
  end

  # The calls of the scripted editor below root.
  def editor_calls(root)
    log = File.join(root, "editor", "calls.jsonl")
    File.exist?(log) ? File.readlines(log).map { JSON.parse(it) } : []
  end
```

- [ ] **Step 2: Write the failing tests**

`test/cli/credentials_edit_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsEditTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  Key = Metacrunch::Credentials::Key

  def test_creates_key_gitignore_and_credentials
    in_tmpdir do |root|
      code, _stdout, stderr = edit(root, scripted_editor(root, "fis:\n  api_key: pässwörd\n"))
      dir = File.join(root, ".metacrunch")
      key = Key.parse(File.read(File.join(dir, "master.key")), source: "test")

      assert_equal 0, code, stderr
      assert_equal "fis:\n  api_key: pässwörd\n", unseal(File.join(dir, "credentials.yml.enc"), key)
      assert_equal ["master*.key\n", 0o600],
                   [File.read(File.join(dir, ".gitignore")), File.stat(File.join(dir, "master.key")).mode & 0o777]
    end
  end

  def test_names_the_new_key_and_the_saved_file
    in_tmpdir do |root|
      _code, _stdout, stderr = edit(root, scripted_editor(root, "a: 1\n"))

      assert_equal "Editing .metacrunch/credentials.yml.enc\nCreated .metacrunch/master.key: keep it safe; " \
                   "it is not committed\nSaved .metacrunch/credentials.yml.enc\n", stderr
    end
  end

  def test_a_new_file_starts_with_a_template_that_names_the_environment
    in_tmpdir do |root|
      edit(root, scripted_editor(root), "-e", "production")
      template = editor_calls(root).first["before"]

      assert_includes template, "(environment: production)"
      assert_includes template, "credential: \"fis.api_key\""
      assert_path_exists File.join(root, ".metacrunch", "credentials.production.yml.enc")
    end
  end

  def test_an_existing_file_is_decrypted_for_the_editor
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, = edit(root, scripted_editor(root, "a: 2\n"))

      assert_equal 0, code
      assert_equal "a: 1\n", editor_calls(root).first["before"]
      assert_equal "a: 2\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_with_the_key_variable_no_key_file_is_written
    in_tmpdir do |root|
      key = Key.generate
      code, = edit(root, scripted_editor(root, "a: 1\n"), env: {"METACRUNCH_MASTER_KEY" => key.hex})

      assert_equal 0, code
      assert_equal "a: 1\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
      refute_path_exists File.join(root, ".metacrunch", "master.key")
    end
  end

  def test_the_plaintext_is_private_and_removed_afterwards
    in_tmpdir do |root|
      edit(root, scripted_editor(root, "a: 1\n"), "-e", "production")
      call = editor_calls(root).first

      assert_equal [0o600, 0o700], [call["mode"], call["dir_mode"]]
      assert_equal "credentials.production.yml", File.basename(call["path"])
      refute_path_exists File.dirname(call["path"])
    end
  end

  def test_a_failing_editor_saves_nothing
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, _stdout, stderr = edit(root, scripted_editor(root, "a: 2\n", status: 3))

      assert_equal 1, code
      assert_includes stderr, "exited with status 3; nothing saved"
      assert_equal "a: 1\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_the_plaintext_is_removed_when_the_editor_fails
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      edit(root, scripted_editor(root, "a: 2\n", status: 3))

      refute_path_exists File.dirname(editor_calls(root).first["path"])
    end
  end

  def test_unchanged_content_writes_nothing_and_says_how_to_make_an_editor_wait
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      file = File.join(root, ".metacrunch", "credentials.yml.enc")
      before = File.binread(file)
      code, _stdout, stderr = edit(root, scripted_editor(root))

      assert_equal 0, code
      assert_includes stderr, "No changes. If your editor returns at once, make it wait, e.g. EDITOR=\"code --wait\"."
      assert_equal before, File.binread(file)
    end
  end

  def test_invalid_yaml_without_a_terminal_saves_nothing
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, _stdout, stderr = edit(root, scripted_editor(root, "a: [\n"))

      assert_equal 1, code
      assert_includes stderr, "invalid YAML in #{root}/.metacrunch/credentials.yml.enc at line 2, column 1"
      assert_equal "a: 1\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_invalid_yaml_on_a_terminal_can_be_edited_again
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, = edit(root, scripted_editor(root, "a: [\n", "a: 2\n"), stdin: TerminalInput.new("\n"))

      assert_equal 0, code
      assert_equal ["a: 1\n", "a: [\n"], editor_calls(root).map { it["before"] }
      assert_equal "a: 2\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_answering_no_saves_nothing
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      code, = edit(root, scripted_editor(root, "a: [\n", "a: 2\n"), stdin: TerminalInput.new("n\n"))

      assert_equal 1, code
      assert_equal 1, editor_calls(root).size
    end
  end

  def test_visual_wins_over_editor
    in_tmpdir do |root|
      failing = Shellwords.join([RbConfig.ruby, "-e", "exit 1"])
      env = {"VISUAL" => scripted_editor(root, "a: 1\n"), "EDITOR" => failing}

      assert_equal 0, Dir.chdir(root) { cli("credentials", "edit", env:) }.first
    end
  end

  def test_without_an_editor_edit_fails
    in_tmpdir do |root|
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "edit") }

      assert_equal 2, code
      assert_includes stderr, "set VISUAL or EDITOR to edit credentials"
    end
  end

  def test_creates_the_directory_in_the_working_directory_not_in_home
    in_tmpdir do |home|
      FileUtils.mkdir_p([File.join(home, ".metacrunch"), File.join(home, "new")])
      env = {"EDITOR" => scripted_editor(home, "a: 1\n"), "HOME" => home}
      Dir.chdir(File.join(home, "new")) { cli("credentials", "edit", env:) }

      assert_path_exists File.join(home, "new", ".metacrunch", "credentials.yml.enc")
      assert_empty Dir.children(File.join(home, ".metacrunch"))
    end
  end

  private

  def edit(root, editor, *options, env: {}, stdin: "")
    Dir.chdir(root) { cli("credentials", "edit", *options, env: env.merge("EDITOR" => editor), stdin:) }
  end

end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/credentials_edit_test.rb`
Expected: failures, because `execute` does not dispatch `edit` yet (it returns nil and writes no file).

- [ ] **Step 4: Write `lib/metacrunch/credentials/editor.rb`**

```ruby
# frozen_string_literal: true

require "shellwords"
require "tmpdir"

module Metacrunch
  module Credentials
    # An edit ended without saving: the editor failed, or invalid YAML was
    # not fixed. The CLI exits with 1.
    class EditAborted < Error; end

    # Lets the user edit plaintext with VISUAL or EDITOR. The plaintext
    # lives in a temporary directory of its own (mode 0700, the file 0600),
    # which is removed in any case.
    class Editor

      def initialize(env:, stdin:, stderr:)
        @env = env
        @stdin = stdin
        @stderr = stderr
      end

      # Returns the edited text. name: the file name the editor sees. The
      # block checks the text and raises CredentialsError if it is invalid;
      # on a terminal the user may then edit again.
      def edit(text, name:)
        command = editor_command
        Dir.mktmpdir("metacrunch-credentials") do |dir|
          path = File.join(dir, name)
          File.open(path, "w", 0o600) { it.write(text) }
          loop do
            run(command, path)
            edited = File.read(path)
            begin
              yield edited
              return edited
            rescue CredentialsError => e
              @stderr.puts("Error: #{e.message}")
              raise EditAborted, "nothing saved" unless again?
            end
          end
        end
      end

      private

      def editor_command
        value = Credentials.present(@env["VISUAL"]) || Credentials.present(@env["EDITOR"])
        raise CredentialsError, "set VISUAL or EDITOR to edit credentials" unless value

        Shellwords.split(value)
      end

      def run(command, path)
        started = system(*command, path)
        return if started

        reason = started.nil? ? "could not be started" : "exited with status #{Process.last_status.exitstatus}"
        raise EditAborted, "editor #{command.first} #{reason}; nothing saved"
      end

      def again?
        return false unless @stdin.tty?

        @stderr.print("Edit again? [Y/n] ")
        answer = @stdin.gets
        !answer.nil? && !answer.strip.downcase.start_with?("n")
      end

    end
  end
end
```

- [ ] **Step 5: Require the editor in the CLI**

In `lib/metacrunch/cli.rb`, before `require_relative "cli/run_options"`, add:

```ruby
require_relative "credentials/editor"
```

- [ ] **Step 6: Add `edit` to the command**

In `lib/metacrunch/cli/credentials.rb`:

Add at the top, after the magic comment:

```ruby

require "fileutils"
```

Add these constants after `SUBCOMMANDS`:

```ruby
      GITIGNORE = "master*.key\n"
      TEMPLATE = <<~YAML
        # Credentials for metacrunch jobs%<environment>s. They are encrypted when you save.
        # A parameter reads a value with credential: "fis.api_key":
        #
        # fis:
        #   api_key: secret
        #
        # Quote values that YAML reads as numbers or booleans: "0123", "yes", "on".
      YAML
```

In `execute`, add the branch and the rescue:

```ruby
        case subcommand
        when "edit" then edit_credentials(location)
        when "show" then show_credentials(location)
        end
      rescue Credentials::EditAborted => e
        @stderr.puts("Error: #{e.message}")
        EXIT_CODES[:aborted]
      end
```

Add these methods after `show_credentials`:

```ruby
      def edit_credentials(location)
        file = location.file
        existing = File.file?(file)
        key = existing ? location.key! : location.key
        text = existing ? unseal(location, key) : template(location.environment)
        @stderr.puts("Editing #{display(file)}")
        edited = editor.edit(text, name: File.basename(file, ".enc")) { Credentials.load_yaml(it, file) }
        return no_changes if existing && edited == text

        prepare(location.directory) unless existing
        key ||= create_key(location)
        Credentials.write(file, Credentials::Box.seal(edited, key), perm: 0o644)
        @stderr.puts("Saved #{display(file)}")
        EXIT_CODES[:ok]
      end

      def template(environment)
        format(TEMPLATE, environment: environment ? " (environment: #{environment})" : "")
      end

      def editor = Credentials::Editor.new(env: @env, stdin: @stdin, stderr: @stderr)

      def no_changes
        @stderr.puts("No changes. If your editor returns at once, make it wait, e.g. EDITOR=\"code --wait\".")
        EXIT_CODES[:ok]
      end

      # A new directory gets a .gitignore that keeps the keys out of git.
      def prepare(directory)
        FileUtils.mkdir_p(directory)
        gitignore = File.join(directory, ".gitignore")
        File.write(gitignore, GITIGNORE) unless File.exist?(gitignore)
      end

      def create_key(location)
        key = Credentials::Key.generate
        Credentials.write(location.key_file, "#{key.hex}\n", perm: 0o600)
        @stderr.puts("Created #{display(location.key_file)}: keep it safe; it is not committed")
        key
      end
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/credentials_edit_test.rb`
Expected: all tests pass.

- [ ] **Step 8: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`

```bash
git add lib/metacrunch/credentials/editor.rb lib/metacrunch/cli.rb lib/metacrunch/cli/credentials.rb \
  test/support/credentials_helper.rb test/cli/credentials_edit_test.rb
git commit -F - <<'EOF'
Add metacrunch credentials edit

edit decrypts into a private temporary directory, runs VISUAL or EDITOR,
checks the YAML (on a terminal it offers to edit again) and encrypts the
result. A new file gets a key, unless METACRUNCH_MASTER_KEY is set, and
a .gitignore for the keys. Unchanged content is not rewritten.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 8: `credentials rotate`

**Files:**
- Modify: `lib/metacrunch/cli/credentials.rb`
- Test: `test/cli/credentials_rotate_test.rb`

**Interfaces:**
- Consumes: `existing_file`, `unseal`, `display` (Task 6); `Credentials.write`, `Box.seal`, `Key.generate` (Task 1); `Location#key!`, `#key_file` (Task 2).
- Produces: `CredentialsCommand#rotate_credentials(location)`.

- [ ] **Step 1: Write the failing tests**

`test/cli/credentials_rotate_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CredentialsRotateTest < Minitest::Test

  include CliHelper
  include CredentialsHelper
  include Override

  Key = Metacrunch::Credentials::Key

  def test_rotate_encrypts_with_a_new_key_in_the_key_file
    in_tmpdir do |root|
      old_key = write_credentials(root, "a: 1\n")
      code, stdout, stderr = Dir.chdir(root) { cli("credentials", "rotate") }
      new_key = Key.parse(File.read(key_file(root)), source: "test")

      assert_equal [0, ""], [code, stdout], stderr
      assert_equal "a: 1\n", unseal(credentials_file(root), new_key)
      assert_raises(Metacrunch::CredentialsError) { unseal(credentials_file(root), old_key) }
    end
  end

  def test_rotate_leaves_only_the_two_files_with_their_modes
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      Dir.chdir(root) { cli("credentials", "rotate") }

      assert_equal ["credentials.yml.enc", "master.key"], Dir.children(File.join(root, ".metacrunch")).sort
      assert_equal [0o644, 0o600], [file_mode(credentials_file(root)), file_mode(key_file(root))]
    end
  end

  def test_with_the_key_variable_the_new_key_goes_to_stdout
    in_tmpdir do |root|
      old_key = write_credentials(root, "a: 1\n", key_file: false)
      env = {"METACRUNCH_MASTER_KEY" => old_key.hex}
      code, stdout, stderr = Dir.chdir(root) { cli("credentials", "rotate", env:) }

      assert_equal 0, code
      assert_equal "a: 1\n", unseal(credentials_file(root), Key.parse(stdout, source: "stdout"))
      assert_includes stderr, "Update METACRUNCH_MASTER_KEY wherever it is set"
    end
  end

  def test_with_the_key_variable_a_key_file_is_reported_as_stale
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      _code, _stdout, stderr = Dir.chdir(root) do
        cli("credentials", "rotate", env: {"METACRUNCH_MASTER_KEY" => key.hex})
      end

      assert_includes stderr, "Warning: .metacrunch/master.key still holds the old key; replace or remove it"
      assert_equal "#{key.hex}\n", File.read(key_file(root))
    end
  end

  def test_a_failure_before_the_renames_changes_nothing
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      before = snapshot(root)
      code = override(File, :rename, ->(*) { raise Errno::EACCES, "test" }) do
        Dir.chdir(root) { cli("credentials", "rotate").first }
      end

      assert_equal 1, code
      assert_equal before, snapshot(root)
    end
  end

  def test_when_the_second_rename_fails_the_new_key_waits_in_a_new_file
    in_tmpdir do |root|
      old_key = write_credentials(root, "a: 1\n")
      code = override(File, :rename, failing_second_rename) { Dir.chdir(root) { cli("credentials", "rotate").first } }
      pending = Key.parse(File.read("#{key_file(root)}.new"), source: "test")

      assert_equal 1, code
      assert_equal "a: 1\n", unseal(credentials_file(root), pending)
      assert_equal "#{old_key.hex}\n", File.read(key_file(root))
    end
  end

  def test_rotate_needs_the_current_key_and_the_file
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n", key_file: false)

      assert_equal 2, Dir.chdir(root) { cli("credentials", "rotate").first }
      assert_equal 2, Dir.chdir(root) { cli("credentials", "rotate", "-e", "production").first }
    end
  end

  private

  def credentials_file(root) = File.join(root, ".metacrunch", "credentials.yml.enc")

  def key_file(root) = File.join(root, ".metacrunch", "master.key")

  def file_mode(path) = File.stat(path).mode & 0o777

  def snapshot(root)
    dir = File.join(root, ".metacrunch")
    Dir.children(dir).sort.to_h { [it, File.binread(File.join(dir, it))] }
  end

  def failing_second_rename
    rename = File.method(:rename)
    calls = 0
    lambda do |from, to|
      calls += 1
      raise Errno::EACCES, "test" if calls == 2

      rename.call(from, to)
    end
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/credentials_rotate_test.rb`
Expected: failures (`rotate` is not dispatched).

- [ ] **Step 3: Add `rotate` to the command**

In `lib/metacrunch/cli/credentials.rb`, add the branch `when "rotate" then rotate_credentials(location)` to the `case` in `execute`, and add these methods after `create_key`:

```ruby
      def rotate_credentials(location)
        file = existing_file(location)
        old_key = location.key!
        plaintext = unseal(location, old_key)
        key = Credentials::Key.generate
        @stderr.puts("Rotating #{display(file)}")
        if old_key.source == Credentials::KEY_VARIABLE
          rotate_variable_key(location, plaintext, key)
        else
          rotate_key_file(location, plaintext, key)
        end
        EXIT_CODES[:ok]
      end

      # The new key goes to stdout once; whoever set the variable updates it.
      def rotate_variable_key(location, plaintext, key)
        Credentials.write(location.file, Credentials::Box.seal(plaintext, key), perm: 0o644)
        @stdout.puts(key.hex)
        @stderr.puts("Update #{Credentials::KEY_VARIABLE} wherever it is set; the old key no longer works")
        return unless File.file?(location.key_file)

        @stderr.puts("Warning: #{display(location.key_file)} still holds the old key; replace or remove it")
      end

      # Both new files are written before either is renamed, so an error
      # until then changes nothing. If the second rename fails,
      # KEY_FILE.new holds the key of the new credentials file.
      def rotate_key_file(location, plaintext, key)
        sealed = "#{location.file}.#{Process.pid}.tmp"
        pending = "#{location.key_file}.new"
        begin
          File.open(sealed, "w", 0o644) { it.write(Credentials::Box.seal(plaintext, key)) }
          File.open(pending, "w", 0o600) { it.write("#{key.hex}\n") }
          File.chmod(0o600, pending)
          File.rename(sealed, location.file)
        rescue StandardError
          [sealed, pending].each { File.unlink(it) if File.exist?(it) }
          raise
        end
        File.rename(pending, location.key_file)
        @stderr.puts("New key in #{display(location.key_file)}")
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/credentials_rotate_test.rb`
Expected: all tests pass.

- [ ] **Step 5: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`

```bash
git add lib/metacrunch/cli/credentials.rb test/cli/credentials_rotate_test.rb
git commit -F - <<'EOF'
Add metacrunch credentials rotate

rotate encrypts the credentials with a new key. A key file is replaced;
a key from METACRUNCH_MASTER_KEY is printed once instead. Both new files
are written before either is renamed, and if the second rename fails the
new key waits in KEY_FILE.new.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 9: End-to-end tests, documentation and measurement

**Files:**
- Test: `test/cli/exe_credentials_test.rb`
- Modify: `Readme.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-10-11-metacrunch-ng-credentials-design.md` (status)

**Interfaces:**
- Consumes: everything above; `exe/metacrunch`.
- Produces: documentation only.

- [ ] **Step 1: Write the end-to-end tests**

`test/cli/exe_credentials_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "open3"

class ExeCredentialsTest < Minitest::Test

  include CredentialsHelper

  ROOT = File.expand_path("../..", __dir__)
  OUTPUT = ("\"#{CredentialsHelper::SECRET.reverse}\"\n" * 2).freeze
  PIN_JOB = <<~RUBY
    # frozen_string_literal: true

    Metacrunch.job do
      params do
        param :pin, Integer, credential: "fis.api_key", required: true
      end

      source [params.pin]
    end
  RUBY

  def test_edit_then_run_from_another_directory
    in_tmpdir do |root|
      project = File.join(root, "project")
      editor = scripted_editor(root, "fis:\n  api_key: #{SECRET}\n")
      _out, edit_err, edit_status = metacrunch("credentials", "edit", env: {"EDITOR" => editor}, chdir: mkdir(project))
      stdout, stderr, status = metacrunch("run", write_file(project, "jobs/secret.rb", SECRET_JOB), chdir: root)

      assert_predicate edit_status, :success?, edit_err
      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_production_with_the_key_variable_and_no_key_file
    in_tmpdir do |root|
      key = write_credentials(root, {"fis" => {"api_key" => SECRET}}, environment: "production", key_file: false)
      env = {"METACRUNCH_ENV" => "production", "METACRUNCH_MASTER_KEY" => key.hex}
      stdout, stderr, status = metacrunch("run", job(root), env:, chdir: root)

      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_production_does_not_fall_back_to_the_file_without_environment
    in_tmpdir do |root|
      write_credentials(root, {"fis" => {"api_key" => SECRET}})
      _stdout, stderr, status = metacrunch("run", "-e", "production", job(root), chdir: root)

      assert_equal 2, status.exitstatus
      assert_includes stderr, "no credentials for environment production in #{root}/.metacrunch"
    end
  end

  def test_the_env_variable_overrides_the_credential
    in_tmpdir do |root|
      write_credentials(root, {"fis" => {"api_key" => SECRET}})
      stdout, _stderr, status = metacrunch("run", job(root), env: {"FIS_API_KEY" => "other"}, chdir: root)

      assert_equal [0, "\"rehto\"\n" * 2], [status.exitstatus, stdout]
    end
  end

  def test_values_from_env_need_neither_key_nor_file
    in_tmpdir do |root|
      stdout, stderr, status = metacrunch("run", job(root), env: {"FIS_API_KEY" => SECRET}, chdir: root)

      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_workers_get_the_secret
    in_tmpdir do |root|
      write_credentials(root, {"fis" => {"api_key" => SECRET}})
      stdout, stderr, status = metacrunch("run", "-w", "2", job(root), chdir: root)

      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_the_secret_appears_in_no_output
    in_tmpdir do |root|
      write_credentials(root, {"fis" => {"api_key" => SECRET}})
      pin = write_file(root, "jobs/pin.rb", PIN_JOB)
      wrong = {"METACRUNCH_MASTER_KEY" => Metacrunch::Credentials::Key.generate.hex}
      runs = [[["run", job(root), "--help"]], [["run", "-v", job(root)]], [["check", "-v", job(root)]],
              [["run", "-v", pin]], [["run", job(root)], wrong], [["run", job(root), "--api-key", SECRET]]]
      outputs = runs.map { |args, env| metacrunch(*args, env: env || {}, chdir: root).take(2).join }

      assert(outputs.none? { it.include?(SECRET) }, outputs.join("\n---\n"))
      assert_includes outputs[3], "(hidden) is not an Integer"
    end
  end

  private

  def job(root) = write_file(root, "jobs/secret.rb", SECRET_JOB)

  def mkdir(path) = path.tap { FileUtils.mkdir_p(it) }

  # Runs exe/metacrunch in chdir. HOME is an empty directory and the
  # variables of the developer's shell that would change a run are unset.
  def metacrunch(*args, chdir:, env: {})
    home = File.join(chdir, ".test-home")
    FileUtils.mkdir_p(home)
    clean = {"HOME" => home, "METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil,
             "METACRUNCH_MASTER_KEY" => nil, "FIS_API_KEY" => nil, "VISUAL" => nil, "EDITOR" => nil}
    Open3.capture3(clean.merge(env), RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"),
                   *args, chdir:)
  end

end
```

- [ ] **Step 2: Run them**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/exe_credentials_test.rb`
Expected: all tests pass. If one fails, fix the code of the task that owns the behaviour, with a failing unit test there first.

- [ ] **Step 3: Readme, parameters**

In `Readme.md`, section "Parameters", add a line to the example after `param :tags,  Array`:

```ruby
  param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key"
```

and replace the sentence

```
`params` must be the first statement of a job. Values come from the command line, then the environment
variable (`env:`, an empty variable counts as unset), then the default.
```

with

```
`params` must be the first statement of a job. Values come from the command line, then the environment
variable (`env:`, an empty variable counts as unset), then the credentials (`credential:`, see
[Credentials](#credentials)), then the default.
```

- [ ] **Step 4: Readme, new section after "Parameters"**

Insert before `## Running jobs`:

````markdown
## Credentials

Parameters can read secrets, such as API keys and passwords, from encrypted files in the project:

```ruby
params do
  param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key", required: true
end
```

```
$ metacrunch credentials edit                    # opens $VISUAL or $EDITOR
$ metacrunch credentials edit -e production
$ metacrunch credentials show -e production
$ metacrunch credentials rotate -e production
```

`edit` creates `.metacrunch/credentials.yml.enc`, which you commit, and the key `.metacrunch/master.key`, which you
never commit (`.metacrunch/.gitignore` excludes it). The file holds YAML: `credential: "fis.api_key"` reads `api_key`
below `fis`. Quote values that YAML reads as numbers or booleans (`"0123"`, `"yes"`, `"on"`).

| Environment | File | Key |
|---|---|---|
| none | `.metacrunch/credentials.yml.enc` | `.metacrunch/master.key` |
| `-e production` or `METACRUNCH_ENV=production` | `.metacrunch/credentials.production.yml.enc` | `.metacrunch/master.production.key` |

Each environment has its own file and key, so laptops and CI need not hold the production key. A run with an
environment never falls back to the file without one.

- **Where:** `--credentials DIR` or `METACRUNCH_CREDENTIALS`, else the nearest `.metacrunch/` above the job file,
  else `~/.metacrunch/` for personal credentials. The directory found decides alone; `-v` logs the file that was
  decrypted. `metacrunch credentials` looks above the working directory and uses `~/.metacrunch/` only with
  `--credentials ~/.metacrunch`.
- **Key:** `METACRUNCH_MASTER_KEY`, else the key file. In containers and CI, set `METACRUNCH_MASTER_KEY`; with Kamal,
  list it under `env: secret:` and provide it in `.kamal/secrets`.
- **Order:** a parameter's value comes from the command line, its `env:` variable, the credentials, then the default,
  so an environment variable overrides a credential. Credentials are decrypted only if a value is needed: a container
  that sets every variable needs neither key nor file. Leave out `env:` to make sure that no inherited variable
  overrides a secret.
- **Secrets:** a parameter with `credential:` is secret. `--help`, error messages and `params.inspect` hide its value,
  and a value on the command line, where `ps` and the shell history show it, gives a warning. What a job does with the
  value, such as logging it or putting it into an exception, is not hidden. `Metacrunch::Testing.run` never reads
  credentials; pass values with `params:`.
- **Rotation:** `rotate` encrypts a file with a new key and replaces the key file, or prints the new key if the old
  one came from `METACRUNCH_MASTER_KEY`. If it is interrupted between its two renames, `master[.ENV].key.new` holds
  the key of the new file; rename it to `master[.ENV].key`.

Keep in mind:

- While the editor runs, `edit` keeps the plaintext in a temporary file (mode 0600 in a directory with mode 0700) and
  removes it afterwards; only SIGKILL leaves it behind.
- The plaintext stays in the memory of every process that uses it, workers included.
- Other processes of the same user can read `METACRUNCH_MASTER_KEY` from a process's environment
  (`/proc/PID/environ` on Linux).
- A lost key cannot be recovered: delete the file and create it again with `edit`.
````

- [ ] **Step 5: Readme, run options**

In the options table of "Running jobs", after the row of `-j`, `--job NAME`, add:

```
| `-e`, `--environment NAME` | Credentials environment (default: `METACRUNCH_ENV`) |
| `--credentials DIR` | Credentials directory (default: `METACRUNCH_CREDENTIALS`, then `.metacrunch/` above the job file, then `~/.metacrunch/`) |
```

- [ ] **Step 5b: Readme, running jobs from Ruby**

In "Running jobs from Ruby", replace

```
`run` takes the job's parameters as command-line arguments, and the environment for parameters with `env:` as
`env:` (default `ENV`). Invalid parameters raise `Metacrunch::ParamError`; errors while the job runs end up in the result.
```

with

```
`run` takes the job's parameters as command-line arguments, and the environment for parameters with `env:` as
`env:` (default `ENV`). Credentials follow the same `env:` (`METACRUNCH_ENV`, `METACRUNCH_CREDENTIALS`,
`METACRUNCH_MASTER_KEY`, `HOME`) and are searched from the job's file. Invalid parameters and unreadable credentials
raise `Metacrunch::ParamError`; errors while the job runs end up in the result.
```

- [ ] **Step 6: CHANGELOG**

In `CHANGELOG.md`, at the end of "### Added" in 5.0.0, add:

```
- Encrypted credentials: parameters read secrets with `credential:` from `.metacrunch/credentials[.ENV].yml.enc`,
  after the command line and `env:`, and hide them in help texts, errors and `inspect`. `metacrunch credentials
  edit|show|rotate` manages the files; `run`, `check` and `trace` take `-e`/`--environment` and `--credentials`.
```

- [ ] **Step 7: Spec status**

In the spec, replace `- Status: approved design; not implemented` with `- Status: approved; implemented`.

- [ ] **Step 8: Measure the engine**

Run three times: `bundle exec ruby --yjit -Ilib bench/executor.rb inline`
Expected: within 5 % of about 62 ns per step and record, 4.0 allocations per record. Credentials are read while parameters are bound, never per record.

- [ ] **Step 9: Lint, full suite, commit**

Run: `bundle exec rubocop && bundle exec rake`
Expected: no offenses; all tests pass; coverage at least 95 % lines and 90 % branches.

```bash
git add test/cli/exe_credentials_test.rb Readme.md CHANGELOG.md \
  docs/superpowers/specs/2026-10-11-metacrunch-ng-credentials-design.md
git commit -F - <<'EOF'
Document credentials and test them end to end

The end-to-end tests run exe/metacrunch from another working directory:
edit then run, production with METACRUNCH_MASTER_KEY, no fallback, env
overriding a credential, env without key and file, workers, and no
secret in any output.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```
