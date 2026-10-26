# frozen_string_literal: true

require "openssl"

# Replaces the author names of publication records with pseudonyms, e.g.
# before the records are shared for an analysis. A pseudonym is a keyed hash
# (HMAC-SHA256) of the name: the same name always gets the same pseudonym,
# and without the key, the "pepper", nobody can find a name by trying names.
# The pepper is a secret, so the job reads it from the encrypted credentials
# in examples/credentials/.metacrunch/, the nearest .metacrunch/ above this
# file (see docs/credentials.md).
#
#   bundle exec metacrunch run -i examples/data/publications.jsonl examples/credentials/pseudonymize.rb | head -n 2
#   bundle exec metacrunch run -v -i examples/data/publications.jsonl examples/credentials/pseudonymize.rb > /dev/null
#   PSEUDONYM_PEPPER=another bundle exec metacrunch run -i examples/data/publications.jsonl \
#     examples/credentials/pseudonymize.rb | head -n 2
#   bundle exec metacrunch credentials show --credentials examples/credentials/.metacrunch
#
# -v logs which credentials file was decrypted; PSEUDONYM_PEPPER wins over
# the credentials. The key in examples/credentials/.metacrunch/master.key is
# public: it is committed only so that this example runs. Never commit a real
# key; `metacrunch credentials edit` creates a .gitignore that keeps keys out.
Metacrunch.job "pseudonymize" do
  params do
    param :pepper, String, env: "PSEUDONYM_PEPPER", credential: "pseudonyms.pepper", required: true,
                           desc: "Secret for the pseudonyms"
  end

  source id: ->(record) { record["id"] }

  # Names that differ only in whitespace get the same pseudonym.
  pseudonym = lambda do |name|
    "author-#{OpenSSL::HMAC.hexdigest("SHA256", params.pepper, name.split.join(" "))[0, 12]}"
  end

  map(name: "pseudonymize") do |record|
    record.merge("authors" => record.fetch("authors", []).map(&pseudonym))
  end
end
