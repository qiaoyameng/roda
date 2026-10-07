require_relative "../spec_helper"

begin
  require 'mail'
rescue LoadError
  warn "mail not installed, skipping mail_processor plugin test"  
else
Mail.defaults do
  retriever_method :test
end

describe "mail_processor plugin" do 
  def new_mail
    m = Mail.new(:to=>'a@example.com', :from=>'b@example.com', :cc=>'c@example.com', :bcc=>'d@example.com', :subject=>'Sub', :body=>'Bod')
    yield m if block_given?
    m
  end

  def check
    @processed.clear
    yield
    @processed
  end

  it "supports processing Mail instances via the routing tree using case insensitive address matchers" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.to('a@example.com') do
        r.handle_from(/@example.com/) do
          processed << :to_a1
        end
        r.handle_from(/\A(.+)@example(\d).com\z/i) do |pre, id|
          processed << :to_a2 << pre << id
        end
        r.handle_cc(['d@example.com', 'c@example.com']) do |ad|
          processed << :to_a3 << ad
        end
        r.handle do
          processed << :to_a4
        end
      end
      r.handle_to('e@example.com') do
        processed << :to_e
      end
      r.handle_rcpt('f@example.com') do
        processed << :to_f
      end
    end

    check{app.process_mail(new_mail)}.must_equal [:to_a1]
    check{app.process_mail(new_mail{|m| m.from 'b2@example2.com'})}.must_equal [:to_a2, "b2", "2"]
    check{app.process_mail(new_mail{|m| m.from 'b2@example12.com'})}.must_equal [:to_a3, 'c@example.com']
    check{app.process_mail(new_mail{|m| m.from 'b2@f.com'; m.cc []})}.must_equal [:to_a4]
    check{app.process_mail(new_mail{|m| m.to 'e@example.com'})}.must_equal [:to_e]
    check{app.process_mail(new_mail{|m| m.to 'f@example.com'})}.must_equal [:to_f]
    check{app.process_mail(new_mail{|m| m.to 'foo@example.com'; m.cc 'f@example.com'})}.must_equal [:to_f]

    app.freeze

    check{app.process_mail(new_mail{|m| m.to 'A@example.com'})}.must_equal [:to_a1]
    check{app.process_mail(new_mail{|m| m.from 'b2@Example2.com'})}.must_equal [:to_a2, "b2", "2"]
    check{app.process_mail(new_mail{|m| m.from 'b2@EXAMPLE12.com'})}.must_equal [:to_a3, 'c@example.com']
    check{app.process_mail(new_mail{|m| m.from 'b2@f.COM'; m.cc []})}.must_equal [:to_a4]
    check{app.process_mail(new_mail{|m| m.to 'E@EXAmple.com'})}.must_equal [:to_e]
    check{app.process_mail(new_mail{|m| m.to 'f@exAMPLe.com'})}.must_equal [:to_f]
    check{app.process_mail(new_mail{|m| m.to 'FOo@eXAMPle.com'; m.cc 'f@eXAMPle.com'})}.must_equal [:to_f]
  end

  it "supports processing Mail instances via the routing tree using body and subject matchers" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_subject('Sub') do
        r.handle_body(/XID: (\d+)/) do |xid|
          processed << :sb << xid
        end
        processed << :s1
      end
      r.handle_subject(['Su', 'Si']) do |sub|
        processed << :s2 << sub
      end
      r.subject(/S([ao])/) do |sub|
        r.handle do
          processed << :s3 <<  sub
        end
      end
    end

    check{app.process_mail(new_mail)}.must_equal [:s1]
    check{app.process_mail(new_mail{|m| m.subject 'Si'})}.must_equal [:s2, 'Si']
    check{app.process_mail(new_mail{|m| m.subject 'Sa'})}.must_equal [:s3, 'a']
    check{app.process_mail(new_mail{|m| m.body 'XID: 1234'})}.must_equal [:sb, '1234']
  end

  it "supports processing Mail instances via the routing tree using header matchers" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_header('X-Test') do |v|
        processed << :x1 << v
      end
      r.handle_header('X-Test2', 'Foo') do
        processed << :x2
      end
      r.handle_header('X-Test2', ['Foo', 'Bar']) do |val|
        processed << :x3 << val
      end
      r.header('X-Test2', /(\d+)/) do |i|
        r.handle do
          processed << :x4 << i
        end
      end
      r.handle do
        processed << :f
      end
    end

    check{app.process_mail(new_mail)}.must_equal [:f]
    check{app.process_mail(new_mail{|m| m.header['X-Test'] = 'Foo'})}.must_equal [:x1, 'Foo']
    check{app.process_mail(new_mail{|m| m.header['X-Test2'] = 'Foo'})}.must_equal [:x2]
    check{app.process_mail(new_mail{|m| m.header['X-Test2'] = 'Bar'})}.must_equal [:x3, 'Bar']
    check{app.process_mail(new_mail{|m| m.header['X-Test2'] = 'foo 3'})}.must_equal [:x4, '3']
  end

  it "calls unhandled_mail block for email not handled by a routing block" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.to('a@example.com') do
        processed << :on_to
      end
      processed << :miss
    end
    app.unhandled_mail do
      processed << :uh << mail.to.first
    end
    check{app.process_mail(new_mail)}.must_equal [:on_to, :uh, 'a@example.com']
    check{app.process_mail(new_mail{|m| m.to 'b@example.com'})}.must_equal [:miss, :uh, 'b@example.com']
  end

  it "calls handled_mail block for email handled by a routing block" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_to('a@example.com') do
        processed << :to
      end
    end
    app.handled_mail do
      processed << :h << mail.to.first
    end
    check{app.process_mail(new_mail)}.must_equal [:to, :h, 'a@example.com']
  end

  it "raises by default for unhandled email" do
    @processed = processed = []
    app(:mail_processor) do |r|
      processed << :miss
    end
    proc{app.process_mail(new_mail)}.must_raise Roda::RodaPlugins::MailProcessor::UnhandledMail
    processed.must_equal [:miss]
  end

  it "allows calling unhandled_mail directly, and not calling either implicitly if called directly" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_to('a@example.com') do
        r.handle_from('b@example.com') do
          processed << :quux
        end
        unhandled_mail "bar"
        processed << :foo
      end
      r.to('d@example.com') do
        r.handle do
          processed << :bar
          unhandled_mail "foo"
        end
      end
      r.handle do
        processed << :baz
      end
    end
    app.unhandled_mail do
      processed << :uh
    end
    app.handled_mail do
      processed << :h
    end
    app.after_mail do
      processed << :a
    end
    check{app.process_mail(new_mail)}.must_equal [:quux, :h, :a]
    check{app.process_mail(new_mail{|m| m.from 'c@example.com'})}.must_equal [:uh, :a]
    check{app.process_mail(new_mail{|m| m.to 'd@example.com'})}.must_equal [ :bar, :uh, :a]
    check{app.process_mail(new_mail{|m| m.to 'e@example.com'})}.must_equal [ :baz, :h, :a]
  end

  it "always calls after_mail after processing an email, even if the mail is not handled" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_to('a@example.com') do
        processed << :t
      end
      r.handle_to('b@example.com') do
        raise
      end
    end
    app.unhandled_mail do
      processed << :uh
    end
    app.after_mail do
      processed << :a
    end
    check{app.process_mail(new_mail)}.must_equal [:t, :a]
    check{app.process_mail(new_mail{|m| m.to 'd@example.com'})}.must_equal [:uh, :a]
    check{proc{app.process_mail(new_mail{|m| m.to 'b@example.com'})}.must_raise RuntimeError}.must_equal [:a]
  end

  it "always calls after_mail after processing an email, even if handled_mail or unhandled_mail hooks raise an exception" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_to('a@example.com') do
        processed << :t
      end
    end
    app.handled_mail do
      processed << :h
      raise "foo"
    end
    app.unhandled_mail do
      processed << :uh
      raise "foo"
    end
    app.after_mail do
      processed << :a
    end
    check{proc{app.process_mail(new_mail)}.must_raise RuntimeError}.must_equal [:t, :h, :a]
    check{proc{app.process_mail(new_mail{|m| m.to 'd@example.com'})}.must_raise RuntimeError}.must_equal [:uh, :a]
  end

  it "should raise RodaError for unsupported address and content matchers" do
    app(:mail_processor) do |r|
      r.subject('Sub') do
        r.subject(Object.new) do
        end
      end
      r.subject('Si') do
        r.from(Object.new) do
        end
      end
    end

    proc{app.process_mail(new_mail)}.must_raise Roda::RodaError
    proc{app.process_mail(new_mail{|m| m.subject 'Si'})}.must_raise Roda::RodaError
  end

  it "supports processing retrieved mail from a mailbox via the routing tree" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_to('a@example.com') do
        processed << :to_a
      end
      r.handle_to('c@example.com') do
        processed.concat(mail.to)
      end
    end
    Mail::TestRetriever.emails = [new_mail]
    check{app.process_mailbox}.must_equal [:to_a]
    Mail::TestRetriever.emails = [new_mail{|m| m.to 'c@example.com'}]
    check{app.process_mailbox}.must_equal ['c@example.com']
    Mail::TestRetriever.emails = [new_mail] * 10
    check{app.process_mailbox}.must_equal([:to_a]*10)
    Mail::TestRetriever.emails = Array.new(10){new_mail}
    check{app.process_mailbox(:count=>2)}.must_equal([:to_a]*2)
    check{app.process_mailbox}.must_equal([:to_a]*8)
  end

  it "supports processing retrieved mail from a mailbox with a custom :retreiver" do
    @processed = processed = []
    emails = []
    retriever = Class.new(Mail::Retriever) do
      define_method(:find) do |opts={}, &block|
        es = emails.dup
        emails.clear
        es.each(&block) if block
        es
      end
    end.new
    app(:mail_processor) do |r|
      r.handle_to('a@example.com') do
        processed << :to_a
      end
    end
    emails << new_mail
    check{app.process_mailbox}.must_equal []
    emails.wont_be_empty
    check{app.process_mailbox(:retriever=>retriever)}.must_equal [:to_a]
    emails.must_be_empty
    check{app.process_mailbox(:retriever=>retriever)}.must_equal []
  end

  it "supports rcpt class method to delegate to blocks by recipient address, falling back to main routing block" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle do
        processed << :f
      end
    end
    app.rcpt('a@example.com') do |r|
      r.handle do
        processed << :a
      end
    end
    app.rcpt(/(.*[bcd])@example.com/, /(.*[bcd]2)@example.com/) do |r, x|
      r.handle do
        processed << :bcd << x
      end
    end
    app.rcpt(/([cde])@example.com(.*)/i) do |r, x, y|
      r.handle do
        processed << :cde << x << y
      end
    end
    app.rcpt('B@EXAMPLE.com', 'c@example.com') do |r|
      r.handle do
        processed << :bc
      end
    end
    app.rcpt('x@example.com') do |r|
      processed << :x
    end
    proc{app.rcpt(Object.new){}}.must_raise Roda::RodaError

    check{app.process_mail(new_mail)}.must_equal [:a]

    app.freeze

    check{app.process_mail(new_mail{|m| m.to 'b@example.com'})}.must_equal [:bc]
    check{app.process_mail(new_mail{|m| m.to 'C@example.com'; m.cc 'a@example.com'})}.must_equal [:bc]
    check{app.process_mail(new_mail{|m| m.to 'd@example.com'; m.cc 'a@example.com'})}.must_equal [:a]
    check{app.process_mail(new_mail{|m| m.to 'd@example.com'; m.cc []})}.must_equal [:bcd, 'd']
    check{app.process_mail(new_mail{|m| m.to '123d@example.com123'; m.cc []})}.must_equal [:bcd, '123d']
    check{app.process_mail(new_mail{|m| m.to 'd2@example.com'; m.cc []})}.must_equal [:bcd, 'd2']
    check{app.process_mail(new_mail{|m| m.to '123d2@example.com123'; m.cc []})}.must_equal [:bcd, '123d2']
    check{app.process_mail(new_mail{|m| m.to 'e@example.com'; m.cc []})}.must_equal [:cde, 'e', '']
    check{app.process_mail(new_mail{|m| m.to '123e@example.com123'; m.cc []})}.must_equal [:cde, 'e', '123']
    check{proc{app.process_mail(new_mail{|m| m.to 'x@example.com'})}.must_raise Roda::RodaPlugins::MailProcessor::UnhandledMail}.must_equal [:x]
  end

  it "supports mail_recipients class method to set recipients of mail, respected by rcpt methods" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_rcpt('a@example.com') do
        processed << :a
      end
      r.handle do
        processed << :f
      end
    end
    app.rcpt('b@example.com') do |r|
      r.handle do
        processed << :b
      end
    end
    check{app.process_mail(new_mail)}.must_equal [:a]
    check{app.process_mail(new_mail{|m| m.to 'b@example.com'})}.must_equal [:b]
    check{app.process_mail(new_mail{|m| m.to 'e@example.com'})}.must_equal [:f]

    app.mail_recipients do
      if smtp_rcpt = header['X-SMTP-To']
        smtp_rcpt = smtp_rcpt.decoded
      end
      Array(smtp_rcpt)
    end
    check{app.process_mail(new_mail)}.must_equal [:f]
    check{app.process_mail(new_mail{|m| m.header['X-SMTP-To'] = 'a@example.com'})}.must_equal [:a]
    check{app.process_mail(new_mail{|m| m.header['X-SMTP-To'] = 'b@example.com'})}.must_equal [:b]
  end

  it "supports #mail_text, .mail_text, and r.text for allowing the ability to extract text from mails" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_text(/Found (foo|bar)/) do |x|
        processed << :f << x
      end
      r.text(/Found (baz|quux)/) do |x|
        r.handle do
          processed << :f2 << x << mail_text
        end
      end
      r.handle do
        processed << :nf << mail_text
      end
    end
    check{app.process_mail(new_mail)}.must_equal [:nf, 'Bod']
    check{app.process_mail(new_mail{|m| m.body "Found bar\n--\nFound foo"})}.must_equal [:f, 'bar']
    check{app.process_mail(new_mail{|m| m.body "> Found baz\nFound quux"})}.must_equal [:f2, 'baz', "> Found baz\nFound quux"]
    @app.mail_text do
      text = mail.body.decoded.gsub(/^>[^\r\n]*\r?\n/m, '')
      text.split(/\r?\n--\r?\n/).last
    end
    check{app.process_mail(new_mail)}.must_equal [:nf, 'Bod']
    check{app.process_mail(new_mail{|m| m.body "Found bar\n--\nFound foo"})}.must_equal [:f, 'foo']
    check{app.process_mail(new_mail{|m| m.body "> Found baz\nFound quux"})}.must_equal [:f2, 'quux', "Found quux"]
  end

  it "works with route_block_args plugin" do
    @processed = processed = []
    app(:bare) do
      plugin :mail_processor
      plugin :route_block_args do
        [to, from]
      end
      route do |t, f|
        request.handle do
          processed << t << f
        end
      end
      handled_mail do
#      processed << :h << mail.to.first
      end
    end
    check{app.process_mail(new_mail)}.must_equal [["a@example.com"], ["b@example.com"]]
  end

  it "processes a mail separately for each explicit envelope recipient with independent results" do
    @processed = processed = []
    app(:mail_processor) do |r|
      processed << [:main, envelope_recipient]
    end
    app.rcpt(/ticket\+(\d+)@example.com/i) do |r, ticket_id|
      r.handle do
        processed << [:ticket, ticket_id]
      end
    end
    app.rcpt('boom@example.com') do |r|
      raise "route failure"
    end

    mail = new_mail do |m|
      m.to 'ticket+1@example.com'
      m.cc 'archive@example.com'
      m.subject 'two tickets, one delivery'
    end
    recipients = [
      'ticket+1@example.com',
      'ticket+2@example.com',
      'boom@example.com',
      'unknown@example.com'
    ]

    results = app.process_mail_envelope(mail, recipients)

    results.map(&:recipient).must_equal recipients
    results.map(&:status).must_equal [:handled, :handled, :failed, :unhandled]
    results.map(&:handled?).must_equal [true, true, false, false]
    results.map(&:failed?).must_equal [false, false, true, false]
    results.map(&:unhandled?).must_equal [false, false, false, true]
    results[2].error.message.must_equal "route failure"
    results[3].error.must_be_kind_of Roda::RodaPlugins::MailProcessor::UnhandledMail
    processed.must_equal [[:ticket, "1"], [:ticket, "2"], [:main, "unknown@example.com"]]

    # Request captures are captured per recipient from their own routing.
    app2 = Class.new(Roda)
    app2.plugin :mail_processor
    app2.route do |r|
      r.handle_rcpt(/ticket\+(\w+)@example.com/i) do |id|
      end
    end
    tagged = new_mail { |m| m.to 'header-only@example.com' }
    results = app2.process_mail_envelope(tagged,
      ['ticket+1@example.com', 'ticket+2@example.com', 'nope@example.com'])
    results.map(&:status).must_equal [:handled, :handled, :unhandled]
    results.map(&:captures).must_equal [["1"], ["2"], []]
    results[0].captures.wont_be_same_as results[1].captures

    # The same message can still be processed through the single message entry,
    # which stops at the first matching rcpt route.
    @processed.clear
    app.process_mail(mail)
    processed.must_equal [[:ticket, "1"]]
  end

  it "uses only explicit envelope recipients for routing, never To/Cc hidden recipients" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_rcpt('header-only@example.com') do
        processed << :header_only
      end
      r.handle do
        processed << :fallback
      end
    end
    app.rcpt('envelope@example.com') do |r|
      r.handle_to('header-only@example.com') do
        processed << [:envelope, to.first, cc.first]
      end
    end
    app.mail_recipients do
      ['custom-recipients-ignored@example.com']
    end

    mail = new_mail do |m|
      m.to 'header-only@example.com'
      m.cc 'cc-only@example.com'
    end

    results = app.process_mail_envelope(mail, ['envelope@example.com', 'other@example.com'])
    results.map(&:status).must_equal [:handled, :handled]
    processed.must_equal [[:envelope, 'header-only@example.com', 'cc-only@example.com'], :fallback]
  end

  it "deduplicates envelope recipients with a case sensitive local part by default, in envelope order" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle do
        processed << envelope_recipient
      end
    end

    mail = new_mail
    recipients = ['Ticket+1@example.com', 'Ticket+1@EXAMPLE.com', 'ticket+1@Example.com']
    results = app.process_mail_envelope(mail, recipients)

    results.map(&:recipient).must_equal ['Ticket+1@example.com', 'ticket+1@Example.com']
    results.map(&:status).must_equal [:handled, :handled]
    processed.must_equal ['Ticket+1@example.com', 'ticket+1@Example.com']

    # Caller can override the comparison, e.g. fully case insensitive addresses.
    @processed.clear
    results = app.process_mail_envelope(mail, recipients,
      address_key: lambda{|address| address.downcase})
    results.map(&:recipient).must_equal ['Ticket+1@example.com']
    processed.must_equal ['Ticket+1@example.com']
  end

  it "supports stopping after a failed recipient while continuing by default" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle do
        processed << envelope_recipient
      end
    end
    app.rcpt('boom@example.com') do |r|
      raise "boom"
    end

    mail = new_mail
    recipients = ['ok1@example.com', 'boom@example.com', 'ok2@example.com']

    results = app.process_mail_envelope(mail, recipients)
    results.map(&:recipient).must_equal recipients
    results.map(&:status).must_equal [:handled, :failed, :handled]
    processed.must_equal ['ok1@example.com', 'ok2@example.com']

    @processed.clear
    results = app.process_mail_envelope(mail, recipients, on_error: :stop)
    results.map(&:recipient).must_equal ['ok1@example.com', 'boom@example.com']
    results.map(&:status).must_equal [:handled, :failed]
    processed.must_equal ['ok1@example.com']

    # Unhandled recipients are not failures and do not stop processing.
    @processed.clear
    app2 = Class.new(Roda)
    app2.plugin :mail_processor
    app2.route do |r|
    end
    results = app2.process_mail_envelope(mail, recipients, on_error: :stop)
    results.map(&:status).must_equal [:unhandled, :unhandled, :unhandled]

    proc{app.process_mail_envelope(mail, recipients, on_error: :abort)}.must_raise Roda::RodaError
  end

  it "runs handled/unhandled/after_mail hooks once per envelope recipient" do
    @processed = processed = []
    app(:mail_processor) do |r|
      r.handle_rcpt('ok@example.com') do
        processed << :route_ok
      end
      r.handle_rcpt('boom@example.com') do
        processed << :route_boom
        raise "boom"
      end
    end
    app.handled_mail do
      processed << [:handled, envelope_recipient]
    end
    app.unhandled_mail do
      processed << [:unhandled, envelope_recipient]
    end
    app.after_mail do
      processed << [:after, envelope_recipient]
    end

    mail = new_mail
    results = app.process_mail_envelope(mail,
      ['ok@example.com', 'missing@example.com', 'boom@example.com'])
    results.map(&:status).must_equal [:handled, :unhandled, :failed]
    processed.must_equal [
      :route_ok, [:handled, 'ok@example.com'], [:after, 'ok@example.com'],
      [:unhandled, 'missing@example.com'], [:after, 'missing@example.com'],
      :route_boom, [:after, 'boom@example.com']
    ]
  end

  it "works with hooks plugin, calling after hook before *_mail hooks" do
    @processed = processed = []
    app(:bare) do
      plugin :mail_processor
      plugin :hooks
      before do 
        processed << 1
      end
      after do |_|
        processed << 2
      end
      route do |r|
        processed << 3
        r.handle_to('a@example.com') do
        end
      end
      handled_mail do
        processed << 4
      end
      unhandled_mail do
        processed << 5
      end
      after_mail do
        processed << 6
      end
    end
    check{app.process_mail(new_mail)}.must_equal [1, 3, 2, 4, 6]
    check{app.process_mail(new_mail{|m| m.to 'x@example.com'})}.must_equal [1, 3, 2, 5, 6]
  end
end
end
