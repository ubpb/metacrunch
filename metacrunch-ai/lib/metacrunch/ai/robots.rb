# frozen_string_literal: true

module Metacrunch
  module Ai

    # robots.txt as RFC 9309 reads it, for one user agent token. Internal; the
    # web client of Fetch and Sitemap::Reader uses it.
    #
    # The group whose User-agent equals the token (case does not matter;
    # several such groups are merged) applies, else the * group, else every
    # path is allowed. Of the Allow and Disallow rules that match a path (its
    # query included), the longest wins, Allow on a tie; * matches anything,
    # a $ at the end anchors the end. Percent-escapes are compared in upper
    # case; unreserved characters written as escapes are not decoded.
    class Robots

      Rule = Data.define(:allow, :pattern, :length)
      Group = Struct.new(:agents, :rules, :delay)
      private_constant :Rule, :Group

      # The delay in seconds the applying group asks for, or nil.
      attr_reader :crawl_delay

      # The URLs of the Sitemap lines, wherever they stand.
      attr_reader :sitemaps

      def self.parse(text, agent: "metacrunch") = new(text.to_s, agent.to_s.downcase)

      def initialize(text, agent)
        @sitemaps = []
        groups = read(text)
        applying = groups.select { it.agents.include?(agent) }
        applying = groups.select { it.agents.include?("*") } if applying.empty?
        @rules = applying.flat_map(&:rules)
        @crawl_delay = applying.filter_map(&:delay).first
      end

      def allowed?(path)
        path = escapes_up(path.to_s)
        return true if path == "/robots.txt"

        best = @rules.select { it.pattern.match?(path) }.max_by { [it.length, it.allow ? 1 : 0] }
        best.nil? || best.allow
      end

      private

      def read(text)
        groups = []
        agents_open = false
        text.delete_prefix("﻿").each_line do |line|
          field, value = line.sub(/#.*/, "").split(":", 2).map(&:strip)
          next if value.nil?

          case field.downcase
          when "user-agent"
            groups << Group.new([], [], nil) unless agents_open
            groups.last.agents << value.downcase
            agents_open = true
          when "allow", "disallow"
            agents_open = false
            groups.last&.rules&.push(rule(field.casecmp?("allow"), value)) unless value.empty?
          when "crawl-delay"
            agents_open = false
            delay = Float(value, exception: false)
            groups.last.delay = delay if groups.last && delay&.positive?
          when "sitemap"
            @sitemaps << value unless value.empty?
          end
        end
        groups
      end

      def rule(allow, path)
        path = escapes_up(path)
        anchored = path.end_with?("$")
        source = Regexp.escape(anchored ? path.chop : path).gsub("\\*", ".*")
        Rule.new(allow:, pattern: Regexp.new("\\A#{source}#{"\\z" if anchored}"), length: path.length)
      end

      def escapes_up(text) = text.gsub(/%[0-9a-f]{2}/i, &:upcase)

    end

    # Allows every path: for a robots.txt that is not there (4xx).
    Robots::ALLOW = Robots.parse("")

  end
end
