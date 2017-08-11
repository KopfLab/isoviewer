# Ruby guard file (need ruby >2.2 and bundler installed: 'gem install bundler')
# To make sure all the gems are installed, run 'bundle install' once in terminal
# Then you can use the Makefile target 'make gui_dev' to start the GUI in development mode
# For browser livereload to work, need the browser extension: http://livereload.com/extensions/#installing-sections
# If the delay is too short for relaunching the app, increase the grace_period

data = 'inst/extdata'
port = 5000

guard 'process', name: 'Shiny', command: ['R', '-e', "devtools::load_all('.'); isoviewer:::turn_debug_on(); isoviewer::run(data_dir = '#{data}', allow_data_upload = TRUE, port = #{port})"] do
  watch(%r{NAMESPACE})
  watch(%r{R/.+\.R$})
end

guard 'livereload', grace_period: 3 do
  watch(%r{NAMESPACE})
  watch(%r{R/.+\.R$})
end
