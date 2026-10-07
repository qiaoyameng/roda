# frozen-string-literal: true

require 'mail'

class Roda
  module RodaPlugins
    # The mail_processor plugin allows your Roda application to process mail
    # using a routing tree. Quick example:
    #
    #   class MailProcessor < Roda
    #     plugin :mail_processor
    #
    #     route do |r|
    #       # Match based on the To header, extracting the ticket_id
    #       r.to /ticket\+(\d+)@example.com/ do |ticket_id|
    #         if ticket = Ticket[ticket_id.to_i]
    #           # Mark the mail as handled if there is a valid ticket associated
    #           r.handle do
    #             ticket.add_note(text: mail_text, from: from)
    #           end
    #         end
    #       end
    #
    #       # Match based on the To or CC header
    #       r.rcpt "post@example.com" do
    #         # Match based on the body, capturing the post id and tag
    #         r.body(/^Post: (\d+)-(\w+)/) do |post_id, tag|
    #           unhandled_mail("no matching post") unless post = Post[post_id.to_i]
    #           unhandled_mail("tag doesn't match for post") unless post.tag == tag
    #
    #           # Match based on APPROVE somewhere in the mail text,
    #           # marking the mail as handled
    #           r.handle_text /\bAPPROVE\b/i do
    #             post.approve!(from)
    #           end
    #
    #           # Match based on DENY somewhere in the mail text,
    #           # marking the mail as handled
    #           r.handle_text /\bDENY\b/i do
    #             post.deny!(from)
    #           end
    #         end
    #       end
    #     end
    #   end
    #
    # = Processing Mail
    #
    # To submit a mail for processing via the mail_processor routing tree, call the +process_mail+
    # method with a +Mail+ instance:
    #
    #   MailProcessor.process_mail(Mail.new do
    #     # ...
    #   end)
    #
    # You can use this to process mail messages from the filesystem:
    #
    #   MailProcessor.process_mail(Mail.read('/path/to/message.eml'))
    #
    # If you have a service that delivers mail via an HTTP POST request (for realtime
    # processing), you can have your web routes convert the web request into a +Mail+ instance
    # and then call +process_mail+:
    #
    #   r.post "email" do
    #     # check request is submitted by trusted sender
    #
    #     # If request body is the raw mail body
    #     r.body.rewind
    #     MailProcessor.process_mail(Mail.new(r.body.read))
    #
    #     # If request body is in a parameter named content
    #     MailProcessor.process_mail(Mail.new(r.params['content']))
    #
    #     # If the HTTP request requires a specific response status code (such as 204)
    #     response.status = 204
    #
    #     nil
    #   end
    #
    # Note that when receiving messages via HTTP, you need to make sure you check that the
    # request is trusted.  How to do this depends on the delivery service, but could involve
    # using HTTP basic authentication, checking for valid API tokens, or checking that a message
    # includes a signature/hash that matches the expected value.
    #
    # If you have setup a default retriever_method for +Mail+, you can call +process_mailbox+,
    # which will process all mail in the given mailbox (using +Mail.find_and_delete+):
    #
    #   MailProcessor.process_mailbox
    #
    # You can also use a +:retreiver+ option to provide a specific retriever:
    #
    #   MailProcessor.process_mailbox(retreiver: Mail::POP3.new)
    #
    # = Routing Mail
    #
    # The mail_processor plugin handles routing similar to Roda's default routing for
    # web requests, but because mail processing may not return a result, the mail_processor
    # plugin uses a more explicit approach to consider whether the message has been handled.
    # If the +r.handle+ method is called during routing, the mail is considered handled,
    # otherwise the mail is considered not handled.  The +unhandled_mail+ method can be
    # called at any point to stop routing and consider the mail as not handled (even if
    # inside an +r.handle+ block).
    #
    # Here are the mail routing methods and what they use for matching:
    #
    # from :: match on the mail From address
    # to :: match on the mail To address
    # cc :: match on the mail CC address
    # rcpt :: match on the mail recipients (To and CC addresses by default)
    # subject :: match on the mail subject
    # body :: match on the mail body
    # text :: match on text extracted from the message (same as mail body by default)
    # header :: match on a mail header
    #
    # All of these routing methods accept a single argument, except for +r.header+, which
    # can take two arguments.
    #
    # Each of these routing methods also has a +r.handle_*+ method
    # (e.g. +r.handle_from+), which will call +r.handle+ implicitly to mark the
    # mail as handled if the routing method matches and control is passed to the block.
    #
    # The address matchers (from, to, cc, rcpt) perform a case-insensitive match if
    # given a string or array of strings, and a regular regexp match if given a regexp.
    #
    # The content matchers (subject, body, text) perform a case-sensitive substring search
    # if given a string or array of strings, and a regular regexp match if given a regexp.
    #
    # The header matcher should be called with a key and an optional value.  If the matcher is
    # called with a key and not a value, it matches if a header matching the key is present
    # in the message, yielding the header value.  If the matcher is called with a key and a
    # value, it matches if a header matching the key is present and the header value matches
    # the value given, using the same criteria as the content matchers.
    #
    # In all cases for matchers, if a string is given and matches, the match block is called without
    # arguments.  If an array of strings is given, and one of the strings matches,
    # the match block is called with the matching string argument.  If a regexp is given,
    # the match block is called with the regexp captures.  This is the same behavior for Roda's
    # general string, array, and regexp matchers.
    # 
    # = Recipient-Specific Routing
    #
    # To allow splitting up the mail processor routing tree based on recipients, you can use
    # the +rcpt+ class method, which takes any number of string or regexps arguments for recipient
    # addresses, and a block to handle the routing for those addresses instead of using the
    # default routing.
    #
    #   MailProcessor.rcpt('a@example.com') do |r|
    #     r.text /Post: (\d+)-(\h+)/ do |post_id, hmac|
    #       next unless Post[post_id.to_i]
    #       unhandled_mail("no matching Post") unless post = Post[post_id.to_i]
    #       unhandled_mail("HMAC for doesn't match for post") unless hmac == post.hmac_for_address(from.first)
    #
    #       r.handle_text 'APPROVE' do
    #         post.approved_by(from)
    #       end
    #
    #       r.handle_text 'DENY' do
    #         post.denied_by(from)
    #       end
    #     end
    #   end
    #
    # The +rcpt+ class method does not mark the messages as handled, because in most cases you will
    # need to do additional matching to extract the information necessary to handle
    # the mail.  You will need to call +r.handle+ or similar method inside the block
    # to mark the mail as handled.
    #
    # Matching on strings provided to the +rcpt+ class method is an O(1) operation as
    # the strings are stored lowercase in a hash.  Matching on regexps provided to the
    # +rcpt+ class method is an O(n) operation on the number of regexps.
    #
   # If you would like to break up the routing tree using something other than the
   # recipient address, you can use the multi_route plugin.
   #
   # = Envelope Processing
   #
   # When a single message is delivered to more than one mailbox, the same Mail
   # instance may have multiple SMTP envelope recipients.  Because +process_mail+
   # determines recipients from the message itself (To and CC headers by
   # default) and returns after the first matching +rcpt+ route, it is not
   # suitable for processing a message independently for each envelope
   # recipient.  For that, use +process_mail_envelope+, passing the Mail
   # instance and the explicit envelope recipient addresses:
   #
   #   results = MailProcessor.process_mail_envelope(mail, envelope_recipients)
   #   results.each do |result|
   #     result.recipient   # the envelope recipient address
   #     result.request     # the Roda request used while routing for it
   #     result.handled?    # r.handle was called for the recipient
   #     result.unhandled?  # no r.handle call and no exception
   #     result.failed?     # an exception was raised, available as result.error
   #   end
   #
   # Only the given envelope addresses are used for recipient-based routing (the
   # class-level +rcpt+ routes and the +r.rcpt+ matcher).  The To and CC headers
   # are not modified and remain available to the routes via +mail.to+ and
   # +mail.cc+, but they are not used to supplement the envelope recipients, so
   # they cannot reveal envelope-only recipients such as BCC addresses.
   #
   # Each recipient is processed with its own Roda scope and request, so request
   # captures and the handled flag are independent per recipient.  Duplicate
   # recipients are processed once.  By default, duplicate detection keeps the
   # case-sensitive local part of the address and compares only the domain part
   # case insensitively (so +Foo@example.com+ and +foo@example.com+ are distinct,
   # but +foo@Example.com+ and +foo@example.com+ are not).  Use the +rcpt_key+
   # class method, or the +:rcpt_key+ option to +process_mail_envelope+, to
   # provide a callable returning the comparison key for an address.
   #
   # By default a failure for one recipient does not prevent the remaining
   # recipients from being processed.  Pass <tt>on_error: :stop</tt> to stop at
   # the first failure, or provide a callable that receives the failing
   # EnvelopeResult and returns +:continue+ or +:stop+.  The returned results
   # are in the order of the given envelope recipients (with duplicates
   # removed), regardless of failures.
   #
   # The +handled_mail+, +unhandled_mail+, and +after_mail+ hooks are invoked
   # for each recipient individually, nested inside that recipient's processing,
   # in the same order as +process_mail+: +handled_mail+ or +unhandled_mail+
   # first (neither runs when routing raises a non-UnhandledMail exception),
   # and +after_mail+ last via +ensure+.  A hook is therefore never invoked more
   # than once for the same recipient.  The default +unhandled_mail+ hook
   # reraises the UnhandledMail exception, but in envelope processing that
   # leaves the recipient unhandled rather than failed, so that one message can
   # be handled for some recipients and unhandled for others.
   #
   # The message itself is not changed, so the same Mail instance can still be
   # passed to +process_mail+ for the standard single-pass processing.
   #
   # = Hooks
   #
    # The mail_processor plugin offers hooks for processing mail.
    #
    # For mail that is handled successfully, you can use the handled_mail hook:
    #
    #   MailProcessor.handled_mail do
    #     # nothing by default
    #   end
    #
    # For mail that is not handled successfully, either because +r.handle+ was not called
    # during routing or because the +unhandled_mail+ method was called explicitly,
    # you can use the unhandled_mail hook.
    #
    # The default is to reraise the UnhandledMail exception that was raised during routing,
    # so that calling code will not be able to ignore errors when processing mail.  However,
    # you may want to save such mails to a special location or forward them as attachments
    # for manual review, and the unhandled_mail hook allows you to do that:
    #
    #   MailProcessor.unhandled_mail do
    #     # raise by default
    #
    #     # Forward the mail as an attachment to an admin
    #     m = Mail.new
    #     m.to 'admin@example.com'
    #     m.subject '[APP] Unhandled Received Email'
    #     m.add_file(filename: 'message.eml', :content=>mail.encoded)
    #     m.deliver
    #   end
    #   
    # Finally, for all processed mail, regardless of whether it was handled or not,
    # there is an after_mail hook, which can be used to archive all processed mail:
    #
    #   MailProcessor.after_mail do
    #     # nothing by default
    #
    #     # Add it to a received_mail table using Sequel
    #     DB[:received_mail].insert(:message=>mail.encoded)
    #   end
    #
    # The after_mail hook is called after the handled_mail or unhandled_mail hook
    # is called, even if routing, the handled_mail hook, or the unhandled_mail hook
    # raises an exception.  The handled_mail and unhandled_mail hooks are not called
    # if an exception is raised during routing (other than for UnhandledMail exceptions).
    #
    # = Extracting Text from Mail
    #
    # The most common use of the mail_processor plugin is to handle replies to mails sent
    # out by the application, so that recipients can reply to mail to make changes without
    # having to access the application directly.  When handling replies, it is common to want
    # to extract only the text of the reply, and ignore the text of the message that was
    # replied to.  Because there is no consistent way to format replies in mail, there have
    # evolved various approaches to do this, with some gems devoted to extracting the reply
    # text from a message.
    #
    # The mail_processor plugin does not choose any particular approach for extracting text from mail,
    # but it includes the ability to configure how to do that via the +mail_text+ class method.
    # This method affects the +r.text+ match method, as well as +mail_text+ instance method.
    # By default, the decoded body of the mail is used as the mail text.
    # 
    #   MailProcessor.mail_text do
    #     # mail.body.decoded by default
    #
    #     # https://github.com/github/email_reply_parser
    #     EmailReplyParser.parse_reply(mail.body.decoded)
    #
    #     # https://github.com/fiedl/extended_email_reply_parser
    #     mail.parse
    #   end
    #
    # = Security
    #
    # Note that due to the way mail delivery works via SMTP, the actual sender and recipient of
    # the mail (the SMTP envelope MAIL FROM and RCPT TO addresses) may not match the sender and
    # receiver embedded in the message.  Because mail_processor routing relies on parsing the mail, 
    # it does not have access to the actual sender and recipient used at the SMTP level, unless
    # a mail server adds that information as a header to the mail (and clears any existing header
    # to prevent spoofing).  Keep that in mind when you are setting up your mail routes.  If you
    # have setup your mail server to add the SMTP RCPT TO information to a header, you may want
    # to only consider that header when looking for the recipients of the message, instead of
    # looking at the To and CC headers.  You can override the default behavior for determining
    # the recipients (this will affect the +rcpt+ class method, +r.rcpt+ match method, and
    # +mail_recipients+ instance method):
    #
    #   MailProcessor.mail_recipients do
    #     # Assuming the information is in the X-SMTP-To header
    #     Array(header['X-SMTP-To'].decoded)
    #   end
    #
    # Also note that unlike when handling web requests where you can rely on storing authentication
    # information in the session, when processing mail, you should manually authenticate each message,
    # as email is trivially forged.  One way to do this is assigning and storing a unique identifier when
    # sending each message, and checking for a matching identifier when receiving a response. Another
    # option is including a computable authentication code (e.g. HMAC) in the message, and then
    # when receiving a response, recomputing the authentication code and seeing if it matches the
    # authentication code in the message.  The unique identifier approach requires storing a large
    # number of identifiers, but allows you to remove the identifier after a reply is received
    # (to ensure only one response is handled).  The authentication code approach does not
    # require additional storage, but does not allow you to ensure only a single response is handled.
    #
    # = Avoiding Mail Loops
    #
    # If processing the mail results in sending out additional mail, be careful not to send a
    # response to the sender of the email, otherwise if the sender of the email has an
    # auto-responder, you can end up with a mail loop, where every mail you send results in
    # a response, which you then process and send out a response to.
    module MailProcessor
      # Exception class raised when a mail processed is not handled during routing,
      # either implicitly because the +r.handle+ method was not called, or via an explicit
      # call to +unhandled_mail+.
      class UnhandledMail < StandardError; end

      # The result of processing a single envelope recipient when using
      # the +process_mail_envelope+ entry point.  Each recipient gets its own
      # result object, so the +request+, +captures+, and +handled?+ values are
      # independent per recipient.
      class EnvelopeResult
        # The envelope recipient address this result is for, in the form it was
        # provided to +process_mail_envelope+.
        attr_reader :recipient

        # The Roda request used when routing for this recipient.  This is a separate
        # request object for each recipient, so request captures do not leak between
        # recipients.
        attr_reader :request

        # The exception that caused processing of this recipient to fail, if any.
        # This is nil for handled and unhandled recipients.
        attr_reader :error

        def initialize(recipient, request) # :nodoc:
          @recipient = recipient
          @request = request
          @error = nil
        end

        # Set the exception that caused this recipient to fail.  The first
        # exception encountered is retained, even if the +after_mail+ hook also
        # raises.
        def fail!(error) # :nodoc:
          @error ||= error
          self
        end

        # Whether routing for the recipient called +r.handle+, marking the
        # recipient as handled.
        def handled?
          request.env['roda.mail_handled'] == true
        end

        # Whether routing for the recipient failed because an exception other
        # than UnhandledMail was raised (during routing, or by one of the
        # +handled_mail+/+after_mail+ hooks).
        def failed?
          !@error.nil?
        end

        # Whether routing for the recipient did not call +r.handle+ and no
        # other exception was raised.
        def unhandled?
          @error.nil? && !handled?
        end
      end

      module ClassMethods
        RodaPlugins.opt_attr_reader(self, :mail_processor_string_routes)
        RodaPlugins.opt_attr_reader(self, :mail_processor_regexp_routes)

        # Freeze the rcpt routes if they are present.
        def freeze
          if string_routes = mail_processor_string_routes.freeze
            string_routes.freeze
            mail_processor_regexp_routes.freeze
          end
          super
        end

        # Process the given Mail instance, calling the appropriate hooks depending on
        # whether the mail was handled during processing.
        def process_mail(mail)
          scope = new(_mail_processor_env(mail))

          begin
            begin
              scope.process_mail
            rescue UnhandledMail
              scope.unhandled_mail_hook
            else
              scope.handled_mail_hook
            end
          ensure
            scope.after_mail_hook
          end
        end

        # Process the given Mail instance once for each of the given envelope
        # recipients.  Unlike +process_mail+, which uses the mail recipients
        # (To and CC headers by default) and stops at the first +rcpt+ route
        # that matches, +process_mail_envelope+ routes the message separately
        # for every explicit envelope recipient address.
        #
        # The envelope recipients are used for all recipient-based routing (the
        # class-level +rcpt+ routes and the +r.rcpt+ matcher).  The To and CC
        # headers are left untouched in the message and remain available via
        # +mail.to+ and +mail.cc+, but they are not consulted to add recipients,
        # so recipients that only appear in the envelope (such as BCC recipients)
        # are not exposed through the headers.
        #
        # Returns an array of EnvelopeResult objects, one for each unique
        # recipient, in the order the recipients were given (duplicate
        # recipients are processed once).  Each result is independently handled,
        # unhandled, or failed:
        #
        #   results = MailProcessor.process_mail_envelope(mail, recipients)
        #   results.each do |result|
        #     case
        #     when result.handled?
        #       # routing called r.handle for result.recipient
        #     when result.failed?
        #       # result.error is the exception raised while processing recipient
        #     when result.unhandled?
        #       # no r.handle call and no exception for result.recipient
        #     end
        #   end
        #
        # Each recipient is routed using a separate Roda scope and request, and
        # the +handled_mail+, +unhandled_mail+, and +after_mail+ hooks are called
        # separately for each recipient, inside the processing of that recipient.
        # For a single recipient the hooks are therefore called at most once, in
        # the same order as +process_mail+: +handled_mail+ or +unhandled_mail+
        # first (neither is called if routing raises a non-UnhandledMail
       # exception), then +after_mail+ in an +ensure+.  An exception raised by
       # the +unhandled_mail+ hook when it is the default hook (which reraises
       # the UnhandledMail exception) leaves the recipient unhandled (with no
       # EnvelopeResult#error); an exception raised by a custom +unhandled_mail+
       # hook, or by any other hook or by routing, marks the recipient as failed.
        #
        # By default, if processing a recipient fails, the remaining recipients
        # are still processed.  Pass <tt>on_error: :stop</tt> to stop processing
        # remaining recipients after the first failure:
        #
        #   MailProcessor.process_mail_envelope(mail, recipients, on_error: :stop)
        #
        # A callable can also be provided, which is called with the failing
        # EnvelopeResult and should return +:continue+ or +:stop+ to determine
        # whether to process the remaining recipients:
        #
        #   MailProcessor.process_mail_envelope(mail, recipients,
        #     on_error: ->(result) { result.error.is_a?(RetryableError) ? :continue : :stop })
        #
        # Duplicate recipients are compared by key.  The default key keeps the
        # case-sensitive local part of the address and only lowercases the domain
        # part, so +Foo@example.com+ and +foo@example.com+ are treated as
        # different recipients, while +foo@Example.com+ and +foo@example.com+
        # are treated as the same.  This key is also used to look up string
        # +rcpt+ routes.  Pass a custom +:rcpt_key+ callable taking the address
        # and returning the comparison key to override this per call:
        #
        #   MailProcessor.process_mail_envelope(mail, recipients,
        #     rcpt_key: ->(address) { address.to_s.downcase })
        #
        # Alternatively, the +rcpt_key+ class method can be used to set the
        # comparison key for all calls.
        def process_mail_envelope(mail, recipients, on_error: :continue, rcpt_key: nil)
          unless on_error.is_a?(Symbol) || on_error.respond_to?(:call)
            raise RodaError, "invalid value for :on_error option, should be :continue, :stop, or a callable"
          end

          routing_scope = new(_mail_processor_env(mail))
          key_callable = rcpt_key || routing_scope.method(:mail_rcpt_key)
          default_unhandled_hook = routing_scope.method(:unhandled_mail_hook).owner == InstanceMethods

          keyed_string_routes = nil
          if string_routes = mail_processor_string_routes
            keyed_string_routes = {}
            string_routes.each do |route_address, meth|
              keyed_string_routes[key_callable.call(route_address)] = meth
            end
          end

          results = []
          seen = {}

          Array(recipients).each do |recipient|
            address = recipient.to_s
            key = key_callable.call(address)
            next if seen.key?(key)
            seen[key] = true

            scope = new(_mail_processor_env(mail, address))
            result = EnvelopeResult.new(recipient, scope.request)
            results << result

            begin
              begin
                scope.process_mail_recipient(address, key, keyed_string_routes)
              rescue UnhandledMail => unhandled
                begin
                  scope.unhandled_mail_hook
                rescue => hook_error
                  # The default unhandled_mail hook just reraises the
                  # UnhandledMail, which represents an unhandled recipient,
                  # not a failure.  Exceptions from custom unhandled_mail
                  # hooks, like all other hook exceptions, mark a failure.
                  unless default_unhandled_hook && hook_error.equal?(unhandled)
                    result.fail!(hook_error)
                  end
                end
              rescue => error
                result.fail!(error)
              else
                begin
                  scope.handled_mail_hook
                rescue => hook_error
                  result.fail!(hook_error)
                end
              end
            ensure
              begin
                scope.after_mail_hook
              rescue => hook_error
                result.fail!(hook_error)
              end
            end

            if result.failed?
              action = on_error.respond_to?(:call) ? on_error.call(result) : on_error
              if action == :stop
                break
              elsif action != :continue
                raise RodaError, "invalid return value from :on_error callable, should be :continue or :stop"
              end
            end
          end

          results
        end
        
        # Process all mail in the given mailbox.  If the +:retriever+ option is
        # given, should be an object supporting the Mail retriever API, otherwise
        # uses the default Mail retriever_method.  This deletes retrieved mail from the
        # mailbox after processing, so that when called multiple times it does
        # not reprocess the same mail.  If mail should be archived and not deleted,
        # the +after_mail+ method should be used to perform the archiving of the mail.
        def process_mailbox(opts=OPTS)
          (opts[:retriever] || Mail).find_and_delete(opts.dup){|m| process_mail(m)}
          nil
        end

        # Setup a routing tree for the given recipient addresses, which can be strings or regexps.
        # Any messages matching the given recipient address will use these routing trees instead
        # of the normal routing tree.
        def rcpt(*addresses, &block)
          opts[:mail_processor_string_routes] ||= {}
          opts[:mail_processor_regexp_routes] ||= {}
          string_meth = nil
          regexp_meth = nil
          addresses.each do |address|
            case address
            when String
              unless string_meth
                string_meth = define_roda_method("mail_processor_string_route_#{address}", 1, &convert_route_block(block))
              end
              mail_processor_string_routes[address] = string_meth 
            when Regexp
              unless regexp_meth
                regexp_meth = define_roda_method("mail_processor_regexp_route_#{address}", :any, &convert_route_block(block))
              end
              mail_processor_regexp_routes[address] = regexp_meth
            else
              raise RodaError, "invalid address format passed to rcpt, should be Array or String"
            end
          end
          nil
        end

        %w'after_mail handled_mail unhandled_mail'.each do |meth|
          class_eval(<<-END, __FILE__, __LINE__+1)
            def #{meth}(&block)
              define_method(:#{meth}_hook, &block)
              nil
            end
          END
        end

        %w'mail_recipients mail_text'.each do |meth|
          class_eval(<<-END, __FILE__, __LINE__+1)
            def #{meth}(&block)
              define_method(:#{meth}, &block)
              nil
            end
          END
        end

        # Set the block used to determine the comparison key for recipient
        # addresses, used when deduplicating envelope recipients and when
        # looking up string +rcpt+ routes during envelope processing.  The
        # block is called with a recipient address and should return the key
        # used for comparison.  By default the local part is preserved as given
        # (case sensitive) and the domain part is lowercased.
        def rcpt_key(&block)
          define_method(:mail_rcpt_key, &block)
          nil
        end

        private

        # Build the Rack environment used to process a mail.  If an envelope
        # recipient address is given, it is stored so recipient routing uses the
        # envelope address instead of the To and CC headers.
        def _mail_processor_env(mail, recipient=nil)
          env = {"PATH_INFO"=>'', "SCRIPT_NAME"=>'', "REQUEST_METHOD"=>"PROCESSMAIL", 'rack.input'=>StringIO.new, 'roda.mail'=>mail}
          env['roda.mail_recipient'] = recipient if recipient
          env
        end
      end

      module InstanceMethods
        [:to, :from, :cc, :body, :subject, :header].each do |field|
          class_eval(<<-END, __FILE__, __LINE__+1)
            def #{field}
              mail.#{field}
            end
          END
        end

        # Perform the processing of mail for this request, first considering
        # routes defined via the class-level +rcpt+ method, and then the
        # normal routing tree passed in as the block.
        def process_mail(&block)
          if string_routes = self.class.mail_processor_string_routes
            addresses = mail_recipients

            addresses.each do |address|
              if meth = string_routes[address.to_s.downcase]
                _roda_handle_route{send(meth, @_request)}
                return
              end
            end

            self.class.mail_processor_regexp_routes.each do |regexp, meth|
              addresses.each do |address|
                if md = regexp.match(address)
                  _roda_handle_route{send(meth, @_request, *md.captures)}
                  return 
                end
              end
            end
          end

          _roda_handle_main_route

          nil
        end

        # Perform the processing of mail for a single explicit envelope
        # recipient, first considering routes defined via the class-level
        # +rcpt+ method (looking up string routes by the given comparison key
        # and regexp routes against the given recipient address), and then the
        # normal routing tree passed in as the block.  This is used by
        # +process_mail_envelope+ so each recipient is routed independently.
        def process_mail_recipient(address, key, keyed_string_routes=nil)
          matched = false

          if keyed_string_routes
            if meth = keyed_string_routes[key]
              _roda_handle_route{send(meth, @_request)}
              matched = true
            end
          end

          unless matched
            if regexp_routes = self.class.mail_processor_regexp_routes
              regexp_routes.each do |regexp, meth|
                if md = regexp.match(address)
                  @_request.captures.concat(md.captures)
                  _roda_handle_route{send(meth, @_request, *md.captures)}
                  matched = true
                  break
                end
              end
            end
          end

          unless matched
            _roda_handle_main_route
          end

          nil
        end

        # Hook called after processing any mail, whether the mail was
        # handled or not.  Does nothing by default.
        def after_mail_hook
          nil
        end

        # Hook called after processing a mail, when the mail was handled.
        # Does nothing by default.
        def handled_mail_hook
          nil
        end

        # Hook called after processing a mail, when the mail was not handled.
        # Reraises the UnhandledMail exception raised during mail processing
        # by default.
        def unhandled_mail_hook
          raise
        end

        # The mail instance being processed.
        def mail
          env['roda.mail']
        end

        # The text of the mail instance being processed, uses the
        # decoded body of the mail by default.
        def mail_text
          mail.body.decoded
        end

        # The recipients of the mail instance being processed, uses the To and CC
        # headers by default.  When processing a specific envelope recipient via
        # +process_mail_envelope+, only that envelope recipient address is
        # returned; the To and CC headers are not used to add recipients.
        def mail_recipients
          return [env['roda.mail_recipient']] if env.key?('roda.mail_recipient')
          Array(to) + Array(cc)
        end

        # The comparison key for a recipient address, used to deduplicate
        # envelope recipients and to look up string +rcpt+ routes during
        # envelope processing.  By default, the local part of the address is
        # kept as given (case sensitive) and the domain part is lowercased,
        # since the domain part of an email address is case insensitive while
        # the local part is case sensitive.  Can be overridden via the
        # +rcpt_key+ class method.
        def mail_rcpt_key(address)
          address = address.to_s
          if idx = address.rindex('@')
            address[0, idx+1] + address[(idx+1)...address.length].downcase
          else
            address
          end
        end

        # Raise an UnhandledMail exception with the given reason, used to mark the
        # mail as not handled.  A reason why the mail was not handled must be
        # provided, which will be used as the exception message.
        def unhandled_mail(reason)
          raise UnhandledMail, reason
        end
      end

      module RequestMethods
        [:to, :from, :cc, :body, :subject, :rcpt, :text].each do |field|
          class_eval(<<-END, __FILE__, __LINE__+1)
            def handle_#{field}(val)
              #{field}(val) do |*args|
                handle do
                  yield(*args)
                end
              end
            end

            def #{field}(address, &block)
              on(:#{field}=>address, &block)
            end
          END

          case field
          when :rcpt, :text, :body, :subject
            next
          end

          class_eval(<<-END, __FILE__, __LINE__+1)
            private

            def match_#{field}(address)
              _match_address(:#{field}, address, Array(mail.#{field}))
            end
          END
        end

        # Same as +header+, but also mark the message as being handled.
        def handle_header(key, value=nil)
          header(key, value) do |*args|
            handle do
              yield(*args)
            end
          end
        end

        # Match based on a mail header value.
        def header(key, value=nil, &block)
          on(:header=>[key, value], &block)
        end

        # Mark the mail as having been handled, so routing will not call
        # unhandled_mail implicitly.
        def handle(&block)
          env['roda.mail_handled'] = true
          always(&block)
        end

        private

        if RUBY_VERSION >= '2.4.0'
          # Whether the addresses are the same (case insensitive match).
          def address_match?(a1, a2)
            a1.casecmp?(a2)
          end
        else
          # simplecov:disable
          def address_match?(a1, a2)
            a1.downcase == a2.downcase
          end
          # simplecov:enable
        end

        # Match if any of the given addresses match the given val, which
        # can be a string (case insensitive match of the string), array of
        # strings (case insensitive match of any string), or regexp
        # (normal regexp match).
        def _match_address(field, val, addresses)
          case val
          when String
            addresses.any?{|a| address_match?(a, val)}
          when Array
            overlap = []
            addresses.each do |a|
              val.each do |v|
                if address_match?(a, v)
                  overlap << a 
                end
              end
            end

            unless overlap.empty?
              @captures.concat(overlap)
            end
          when Regexp
            matched = false
            addresses.each do |v|
              if md = val.match(v)
                matched = true
                @captures.concat(md.captures)
              end
            end
            matched
          else
            unsupported_matcher(:field=>val)
          end
        end

        # Match if the content matches the given val, which
        # can be a string (case sensitive substring match), array of
        # strings (case sensitive substring match of any string), or regexp
        # (normal regexp match).
        def _match_content(field, val, content)
          case val
          when String
            content.include?(val)
          when Array
            val.each do |v|
              if content.include?(v)
                return @captures << v
              end
            end
            false
          when Regexp
            if md = val.match(content)
              @captures.concat(md.captures)
            end
          else
            unsupported_matcher(field=>val)
          end
        end

        # Match the value against the full mail body.
        def match_body(val)
          _match_content(:body, val, mail.body.decoded)
        end

        # Match the value against the mail subject.
        def match_subject(val)
          _match_content(:subject, val, mail.subject)
        end

        # Match the given address against all recipients in the mail.
        def match_rcpt(address)
          _match_address(:rcpt, address, scope.mail_recipients)
        end

        # Match the value against the extracted mail text.
        def match_text(val)
          _match_content(:text, val, scope.mail_text)
        end

        # Match against a header specified by key with the given
        # value (which may be nil).
        def match_header((key, value))
          return unless content = mail.header[key]

          if value.nil?
            @captures << content.decoded
          else
            _match_content(:header, value, content.decoded)
          end
        end

        # The mail instance being processed.
        def mail
          env['roda.mail']
        end

        # If the routing did not explicitly mark the mail as handled
        # mark it as unhandled.
        def block_result_body(_)
          unless env['roda.mail_handled']
            scope.unhandled_mail('mail was not handled during mail_processor routing')
          end
        end
      end
    end

    register_plugin(:mail_processor, MailProcessor)
  end
end
