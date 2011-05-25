require 'spec_helper'
require 'support/vcr'
require 'drop'

describe Drop do

  it 'returns a hash of itself' do
    data = { :name => 'The Guide' }
    drop = Drop.new data

    assert { drop.data == data }
  end

  it 'is not an image' do
    drop = Drop.new :item_type => 'text'

    deny { drop.image? }
  end

  it 'is an image' do
    drop = Drop.new :item_type => 'image'

    assert { drop.image? }
  end

  it 'is not a bookmark' do
    drop = Drop.new :item_type => 'text'

    deny { drop.bookmark? }
  end

  it 'is a bookmark' do
    drop = Drop.new :item_type => 'bookmark'

    assert { drop.bookmark? }
  end

  it 'is not text' do
    drop = Drop.new :item_type  => 'image',
                    :content_url => 'http://f.cl.ly/items/hhgttg/cover.png'

    deny { drop.text? }
  end

  it 'is text' do
    drop = Drop.new :item_type  => 'text',
                    :content_url => 'http://f.cl.ly/items/hhgttg/chapter1.txt'

    assert { drop.text? }
  end

  it 'is not markdown' do
    drop = Drop.new :item_type  => 'image',
                    :content_url => 'http://f.cl.ly/items/hhgttg/cover.png'

    deny { drop.markdown? }
  end

  it 'is markdown with the extension md' do
    drop = Drop.new :item_type  => 'unknown',
                    :content_url => 'http://f.cl.ly/items/hhgttg/chapter1.md'

    assert { drop.markdown? }
    assert { drop.text? }
  end

  it 'is markdown with the extension mdown' do
    drop = Drop.new :item_type  => 'unknown',
                    :content_url => 'http://f.cl.ly/items/hhgttg/chapter1.mdown'

    assert { drop.markdown? }
    assert { drop.text? }
  end

  it 'is markdown with the extension markdown' do
    drop = Drop.new :item_type  => 'unknown',
                    :content_url => 'http://f.cl.ly/items/hhgttg/chapter1.markdown'

    assert { drop.markdown? }
    assert { drop.text? }
  end

  it 'finds a drop' do
    EM.synchrony do
      VCR.use_cassette 'bookmark' do
        drop = Drop.find 'hhgttg'
        EM.stop

        assert { drop.is_a? Drop }
        assert { drop.href         == 'http://my.cl.ly/items/4268562' }
        assert { drop.redirect_url == 'http://getcloudapp.com/download' }
        assert { drop.remote_url.nil? }
      end
    end
  end

  it 'finds an image' do
    EM.synchrony do
      VCR.use_cassette 'image' do
        drop = Drop.find 'hhgttg'
        EM.stop

        assert { drop.is_a? Drop }
        assert { drop.href       == 'http://my.cl.ly/items/307' }
        assert { drop.remote_url == 'http://f.cl.ly/items/hhgttg/cover.png'}
        assert { drop.redirect_url.nil? }
      end
    end
  end

  it 'raises a DropNotFound error' do
    EM.synchrony do
      VCR.use_cassette 'nonexistent' do
        assert { rescuing { Drop.find('hhgttg') }.is_a? Drop::NotFound }

        EM.stop
      end
    end
  end

  it "doesn't have content" do
    drop = Drop.new :item_type  => 'image',
                    :content_url => 'http://f.cl.ly/items/hhgttg/cover.png'

    assert { drop.content.nil? }
  end


  #it 'fetches the content of a text file' do
    #VCR.use_cassette 'text' do
      #EM.run do
        #drop = Drop.find('hhgttg')

        #drop.errback { failed drop }
        #drop.callback do
          #EM.stop

          #assert drop.content.start_with?('Chapter 1')
        #end
      #end
    #end
  #end
  #it 'has content' do
    #VCR.use_cassette 'text' do
      #drop = Drop.new :item_type  => 'text',
                      #:content_url => 'http://f.cl.ly/items/hhgttg/chapter1.txt'

      #assert drop.content.start_with?('Chapter 1')
    #end
  #end

  #it 'fetches and parses the content of a markdown file' do
    #VCR.use_cassette 'markdown' do
      #EM.run do
        #drop = Drop.find('hhgttg')

        #drop.errback { failed drop }
        #drop.callback do
          #EM.stop

          #assert drop.content.start_with?('<h1>Chapter 1</h1>')
        #end
      #end
    #end
  #end
  #it 'parses markdown content' do
    #VCR.use_cassette 'markdown' do
      #drop = Drop.new :item_type  => 'unknown',
                      #:content_url => 'http://f.cl.ly/items/hhgttg/chapter1.md'


      #assert drop.content.start_with?('<h1>Chapter 1</h1>')
    #end
  #end

end
