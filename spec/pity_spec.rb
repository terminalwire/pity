# frozen_string_literal: true

RSpec.describe Pity do
  it "has a version number" do
    expect(Pity::VERSION).not_to be nil
  end

  it "does something useful" do
    Pity::REPL.new do |it|
      it.puts "ls"
      expect(it.gets).to include "README.md"
    end
  end
end
