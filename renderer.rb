#!/usr/bin/env ruby

#require 'FileUtils'
require 'ruby-progressbar'
require 'optparse'
require 'ostruct'
require 'active_support'
require 'active_support/core_ext'

# DEFAULT_BATCH_SIZE = 1000
VIDEO_MANIFEST_FILE = 'filelist.txt'
RENDER_PATH = 'ruby_render'
MAX_THREADS = 5


# Setup command line parser
class OptParse
	def self.parse(args)
		options = OpenStruct.new

		#default values
		options.batch_size = 1000
		options.max_threads = 10


		opts = OptionParser.new do |opts|
			opts.banner = "Usage: ruby #{$0} [options]"
			opts.separator ""
      		opts.separator "Specific options:"

			opts.on("-b", "--blendfile BLEND_FILE", "name of .blend file") do |blend|
				options.blend = blend
			end

			opts.on("-s","--start_frame FRAME_NUMBER", "Starting frame number") do |sframe|
				options.start = sframe.to_i
			end

			opts.on("-e","--end_frame FRAME_NUMBER", "Ending frame number") do |eframe|
				options.end = eframe.to_i
			end

			opts.on("-t", "--threads THREAD_COUNT (default #{options.max_threads}", "Number of threads") do |thread_count|
				options.max_threads = thread_count
			end

			opts.on("--batch_size","--batch_size BATCH_SIZE (default #{options.batch_size}", "Number of frames per batch") do |batch_Size|
				options.batch_size = batch_size
			end

			opts.on_tail("-h", "--help", "Show this message") do
				puts opts
				exit
			end
		end
		
		opts.parse! args
		return options
	end
end

# validate options provided
def validate_opts (opts)
	errors = []
	if opts.start.nil? then
		errors << "- No start frame specified"
	end
	if opts.end.nil? then
		errors << "- No end frame provided"
	end
	if opts.blend.nil? then
		errors << "- No blend-file provided"
	end

	unless errors.empty?
		puts "Errors:"
		errors.each do |err|
			puts err
		end
		OptParse.parse(['-h'])
		exit
	end
end




class Renderer

	def initialize(params)
		@start = params[:start]
		@end = params[:end]
		@blend = params[:blend]

		@batch_size = params[:batch_size] || DEFAULT_BATCH_SIZE
		@batches = []
		define_batches
		
	end

	def create_progress_bar
		@progress_bar = ProgressBar.create(
			:total => @batches.size,
			:format => "%t (%E): |%B|"
		)
	end

	def define_batches
		total_frames = @end - @start + 1
		# total_frames = options.end - options.start + 1
		extra_frames = total_frames % @batch_size

		if extra_frames == total_frames
			@batches << [@start, @end]
			# @batches << [options.start, options.end]
		else
			batches_count = total_frames / @batch_size
			batches_count.times do |batch|
				s_frame = @start + (@batch_size * batch)
				# s_frame = options.start + (@batch_size * batch)
				e_frame = s_frame + @batch_size - 1
				@batches << [s_frame, e_frame]
			end
			@batches << [(@end + 1 - extra_frames), @end] 
			# @batches << [(options.end + 1 - extra_frames), options.end]
		end
	end

	def write_video_manifest
		unless File.exists?(RENDER_PATH)
			Dir.mkdir(RENDER_PATH)
		end
		File.open("#{RENDER_PATH}/#{VIDEO_MANIFEST_FILE}", 'w') {|file|
			@batches.each do |batch|
				sframe, eframe = "%04d" % batch[0], "%04d" % batch[1]
				file.print "file #{sframe}-#{eframe}.mp4\n"
			end
		}
	end

	def render_videos	
		threads = []
		queue = Queue.new
		@batches.each {|sframe, eframe| queue.enq [sframe, eframe]}
		mutex = Mutex.new

		create_progress_bar

		MAX_THREADS.times do 
			threads << Thread.new do
				while !queue.empty? do
					sframe,eframe = queue.pop
					# puts "blender -b #{@blend} -s #{sframe} -e #{eframe} -t 4 -a"
					%x(blender -b #{@blend} --render-output //#{RENDER_PATH}/ -s #{sframe} -e #{eframe} -t 4 -a)
					# %x(blender -b #{options.blend} --render-output //#{RENDER_PATH}/ -s #{sframe} -e #{eframe} -t 4 -a)
					mutex.synchronize {
						@progress_bar.increment
					}
					# cmd = "blender -b //untitled.blend" + " -s " + sframe.to_s + " -e " + eframe.to_s + " -t 4 -a"
					# pid = spawn cmd
					# Process.wait pid
				end
			end
		end
		threads.each{|t| t.join}
	end

	def concat_videos
		Dir.chdir(RENDER_PATH){
			%x(ffmpeg -f concat -i #{VIDEO_MANIFEST_FILE} -c copy -loglevel quiet final.mp4)
		
			@batches.each do |sframe, eframe|
				start_frame, end_frame = "%04d" % sframe, "%04d" % eframe
				# puts "Deleting #{start_frame}-#{end_frame}.mp4"
				FileUtils.rm("#{start_frame}-#{end_frame}.mp4")
			end
			FileUtils.rm(VIDEO_MANIFEST_FILE)
		}
	end

	def render
		start_time = Time.now
		puts "\nProcess started at: #{start_time.strftime("%I:%M:%S %p")}\n"

		write_video_manifest
		render_videos
		concat_videos
		end_time = Time.now
		puts "Process completed at: #{end_time.strftime("%I:%M:%S %p")}"
		# puts "Total time to render: #{Time.at(end_time - start_time).strftime("%H:%M:%S")}"
	end
end


if __FILE__ == $0

	options = OptParse.parse(ARGV)
	validate_opts options

	renderer = Renderer.new(
		:start => options.start,
		:end => options.end,
		:blend => options.blend,
		:batch_size => options.batch_size
	)

	renderer.render
end