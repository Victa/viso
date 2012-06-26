require 'content/code'

describe Content::Code do
  before do
    module FakeSuper
      def content
        'super content'
      end
    end

    class FakeContent
      include FakeSuper
      include Content::Code

      def initialize(content_url, line_numbers = true)
        @content_url  = content_url
        @line_numbers = line_numbers
      end

      def raw
        "puts 'Hello, world!'"
      end
      alias_method :escaped_raw, :raw
    end
  end

  after do
    Object.send :remove_const, :FakeContent
    Object.send :remove_const, :FakeSuper
  end


  describe '#content' do
    it 'syntax highlights content' do
      drop = FakeContent.new 'http://cl.ly/hhgttg/hello.rb'
      code = '<div class="highlight"><pre><span class="nb">puts</span>'

      drop.content.should include(code)
    end

    it 'excludes line numbers' do
      drop  = FakeContent.new 'http://cl.ly/hhgttg/hello.rb', false
      lines = '<td class="linenos">'

      drop.content.should_not include(lines)
    end

    it 'includes line numbers' do
      drop  = FakeContent.new 'http://cl.ly/hhgttg/hello.rb'
      lines = '<table class="highlighttable"><tr><td class="linenos"><div class="linenodiv">'

      drop.content.should include(lines)
    end

    it 'calls #super for non-code files' do
      drop = FakeContent.new 'http://cl.ly/hhgttg/chapter1.txt'

      drop.content.should == 'super content'
    end

    it "doesn't highlight large code files" do
      code     = "puts 123\n" * 5_556
      expected = %{<div class="highlight"><pre><code>#{ code }</code></pre></div>}

      drop = FakeContent.new 'http://cl.ly/hhgttg/hello.rb'
      drop.stub! :raw => code, :escaped_raw => code

      drop.content.should == expected
    end

    it 'escapes html in large code files' do
      code     = "puts 123\n" * 5_556
      escaped  = 'escaped'
      expected = %{<div class="highlight"><pre><code>#{ escaped }</code></pre></div>}

      drop = FakeContent.new 'http://cl.ly/hhgttg/hello.rb'
      drop.stub! :raw => code, :escaped_raw => escaped

      drop.content.should == expected
    end
  end

  describe '#code?' do
    it 'is true when a ruby file' do
      drop = FakeContent.new 'http://cl.ly/hhgttg/hello.rb'

      drop.should be_code
    end

    it 'is false when an image' do
      drop = FakeContent.new 'http://cl.ly/hhgttg/cover.png'

      drop.should_not be_code
    end

    %w( ps md txt ).each do |ext|
      it "is false when a #{ ext.upcase } file" do
        drop = FakeContent.new "http://cl.ly/hhgttg/chapter1.#{ ext }"

        drop.should_not be_code
      end
    end
  end

end
