# frozen_string_literal: true

# Emits records without end and rejects the even ones.
Metacrunch.job do
  source((1..).lazy.map { {"n" => it} })
  reject("Even") { it["n"].even? }
end
