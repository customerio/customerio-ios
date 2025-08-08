#!/usr/bin/env ruby

require 'fileutils'
require 'tmpdir'
require 'digest'

# Script to detect API changes by comparing before/after states
# This script captures current API docs, regenerates them, and reports differences

class ApiChangeDetector
  def initialize
    @docs_dir = 'api-docs'
    @generation_script = './scripts/generate-api-docs.sh'
    @changes_detected = false
    @added_files = []
    @removed_files = []
    @modified_files = []
  end

  def run
    puts colorize("🔍 Starting API change detection...", :blue)
    
    Dir.mktmpdir('api-docs-snapshot') do |temp_dir|
      @temp_dir = temp_dir
      
      capture_current_state
      generate_fresh_docs
      capture_new_state
      compare_states
      report_results
    end
  end

  private

  def capture_current_state
    puts colorize("📸 Capturing current API documentation state...", :yellow)
    
    @before_dir = File.join(@temp_dir, 'before')
    FileUtils.mkdir_p(@before_dir)
    
    if Dir.exist?(@docs_dir)
      FileUtils.cp_r(@docs_dir, @before_dir)
      puts colorize("✅ Current API docs captured", :green)
    else
      puts colorize("⚠️  No existing API docs found, will treat all generated docs as new", :yellow)
    end
  end

  def generate_fresh_docs
    puts colorize("\n🔄 Generating fresh API documentation...", :yellow)
    
    unless File.executable?(@generation_script)
      puts colorize("❌ Generation script not found or not executable: #{@generation_script}", :red)
      exit 1
    end
    
    # Always set CI=1 to ensure internal modules are generated for complete comparison
    success = system({'CI' => '1'}, @generation_script)
    
    if success
      puts colorize("✅ API documentation generation completed", :green)
    else
      puts colorize("❌ API documentation generation failed", :red)
      exit 1
    end
  end

  def capture_new_state
    puts colorize("\n📸 Capturing new API documentation state...", :yellow)
    
    @after_dir = File.join(@temp_dir, 'after')
    FileUtils.mkdir_p(@after_dir)
    
    if Dir.exist?(@docs_dir)
      FileUtils.cp_r(@docs_dir, @after_dir)
      puts colorize("✅ New API docs captured", :green)
    else
      puts colorize("❌ No API docs found after generation", :red)
      exit 1
    end
  end

  def compare_states
    puts colorize("\n🔍 Comparing API documentation states...", :blue)
    
    # Get all API files from both states
    before_files = get_api_files(@before_dir)
    after_files = get_api_files(@after_dir)
    all_files = (before_files + after_files).uniq.sort
    
    all_files.each do |relative_path|
      before_file = File.join(@before_dir, @docs_dir, relative_path)
      after_file = File.join(@after_dir, @docs_dir, relative_path)
      
      if !File.exist?(before_file) && File.exist?(after_file)
        # File was added
        @added_files << relative_path
        @changes_detected = true
      elsif File.exist?(before_file) && !File.exist?(after_file)
        # File was removed
        @removed_files << relative_path
        @changes_detected = true
      elsif File.exist?(before_file) && File.exist?(after_file)
        # File exists in both, check if modified
        unless files_identical?(before_file, after_file)
          @modified_files << {
            path: relative_path,
            before_file: before_file,
            after_file: after_file
          }
          @changes_detected = true
        end
      end
    end
  end

  def report_results
    puts colorize("\n📊 API Change Detection Results:", :blue)
    puts "=" * 48
    
    unless @changes_detected
      puts colorize("✅ No API changes detected", :green)
      puts "All API documentation files are identical to the previous state."
      return
    end
    
    puts colorize("🚨 API changes detected!", :red)
    puts
    
    # Report added files
    if @added_files.any?
      puts colorize("📄 Added files (#{@added_files.length}):", :green)
      @added_files.each { |file| puts "  + #{file}" }
      puts
    end
    
    # Report removed files
    if @removed_files.any?
      puts colorize("🗑️  Removed files (#{@removed_files.length}):", :red)
      @removed_files.each { |file| puts "  - #{file}" }
      puts
    end
    
    # Report modified files
    if @modified_files.any?
      puts colorize("📝 Modified files (#{@modified_files.length}):", :yellow)
      @modified_files.each do |file_info|
        puts "  ~ #{file_info[:path]}"
        
        # Show summary of changes
        changes = analyze_changes(file_info[:before_file], file_info[:after_file])
        puts "    Changes: +#{changes[:added]} lines, -#{changes[:deleted]} lines"
      end
      puts
    end
    
    # Provide actionable next steps
    puts colorize("💡 Next steps:", :blue)
    puts "1. Review the API changes above"
    puts "2. If changes are intentional:"
    puts "   - Update API docs baseline by running `CI=1 ./scripts/generate-api-docs.sh`"
    puts "3. If changes are unintentional:"
    puts "   - Revert API changes"
    
    # Show how to see detailed diffs
    if @modified_files.any?
      puts
      puts colorize("🔍 To see detailed changes, run:", :yellow)
      @modified_files.each do |file_info|
        puts "  diff -u \"#{file_info[:before_file]}\" \"#{file_info[:after_file]}\""
      end
    end
    
    exit 1
  end

  def get_api_files(base_dir)
    docs_path = File.join(base_dir, @docs_dir)
    return [] unless Dir.exist?(docs_path)
    
    Dir.glob(File.join(docs_path, '**', '*.api')).map do |file|
      file.sub("#{docs_path}/", '')
    end
  end

  def files_identical?(file1, file2)
    return false unless File.exist?(file1) && File.exist?(file2)
    
    # Use file size as a quick check
    return false if File.size(file1) != File.size(file2)
    
    # Compare content with checksums for efficiency
    Digest::SHA256.file(file1).hexdigest == Digest::SHA256.file(file2).hexdigest
  end

  def analyze_changes(before_file, after_file)
    before_lines = File.readlines(before_file)
    after_lines = File.readlines(after_file)
    
    # Simple line-based diff analysis
    added = after_lines.length - before_lines.length
    deleted = added < 0 ? -added : 0
    added = added > 0 ? added : 0
    
    # For more accurate counts, we could implement a proper diff algorithm
    # but this gives a reasonable approximation
    
    { added: added, deleted: deleted }
  end

  def colorize(text, color)
    colors = {
      red: "\033[0;31m",
      green: "\033[0;32m",
      yellow: "\033[1;33m",
      blue: "\033[0;34m",
      reset: "\033[0m"
    }
    
    "#{colors[color]}#{text}#{colors[:reset]}"
  end
end

# Run the detector
if __FILE__ == $0
  detector = ApiChangeDetector.new
  detector.run
end 