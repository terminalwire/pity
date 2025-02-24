# frozen_string_literal: true

require_relative "pity/version"
require 'pty'
require 'io/console'
require 'logger'

module Pity
  class Error < StandardError; end

  class REPL
    attr_reader :stdout, :stdin, :logger

    # Number of bytes to read at a time.
    READ_CHUNK_SIZE = 512

    # Seconds to wait in IO.select before retrying.
    SELECT_TIMEOUT = 0.01

    # How long to wait before giving up on a read.
    TIMEOUT = 5

    # How long to wait before giving up on a prompt capture.
    PROMPT_CAPTURE_TIMEOUT = 1

    def initialize(command = "bash", prompt: nil, logger: self.class.logger)
      @logger = logger
      @stdout, @stdin, @pid = PTY.spawn(command)
      @stdout.sync = true
      @stdin.sync = true
      logger.debug "Spawned process with PID #{@pid} using command: #{command}"

      captured = prompt || capture_initial_prompt
      @prompt = Regexp.new(Regexp.escape(captured) + '\z')
      logger.debug "Captured prompt: #{captured.inspect}"

      begin
        yield self
      ensure
        cleanup
      end
    end

    def puts(input)
      @stdin.puts(input)
      logger.debug "Sent: #{input}"
    end

    def gets(**)
      expect(@prompt, **)
    end

    def expect(expectation, **)
      read_until(**) { |buf| buf.match(expectation) }
    end

    private

    def read_until(timeout: TIMEOUT)
      buffer = +""
      start_time = Time.now

      loop do
        break if (Time.now - start_time) > timeout
        begin
          char = @stdout.read_nonblock(READ_CHUNK_SIZE)
          buffer << char
          break if yield(buffer)
        rescue IO::WaitReadable
          IO.select([@stdout], nil, nil, SELECT_TIMEOUT) and retry
        rescue EOFError
          break
        end
      end

      logger.info buffer
      logger.debug "Read: #{buffer.inspect}"
      buffer
    end

    def capture_initial_prompt(timeout: PROMPT_CAPTURE_TIMEOUT, **)
      read_until(timeout:, **) { |buf| buf.include?("\n") }.chomp
    end

    def cleanup
      Process.kill('TERM', @pid)
      logger.debug "Terminated process with PID #{@pid}"
    rescue Errno::ESRCH
      logger.debug "Process #{@pid} was already terminated."
    end

    def self.logger
      Logger.new(STDOUT).tap do |log|
        log.level = Logger::INFO
        log.formatter = proc do |severity, _datetime, _progname, msg|
          case severity
          when "INFO"
            msg
          else
            "#{msg}\n"
          end
        end
      end
    end
  end
end
