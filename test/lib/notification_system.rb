require_relative 'error_handler'
require_relative 'logging'
require 'json'

module MitamaeTest
  # Local notification system for long-running test completion
  class NotificationSystem
    include Logging
    
    NOTIFICATION_TYPES = {
      desktop: 'Desktop notifications using system tools',
      terminal: 'Terminal bell and status messages',
      webhook: 'HTTP webhook notifications',
      email: 'Email notifications (requires configuration)',
      slack: 'Slack webhook notifications',
      file: 'File-based notifications for scripts'
    }.freeze
    
    attr_reader :enabled_notifications, :configuration
    
    def initialize(configuration = {})
      @configuration = configuration
      @enabled_notifications = determine_enabled_notifications
      @notification_history = []
      
      log_debug "Notification system initialized with: #{@enabled_notifications.join(', ')}"
    end
    
    # Send test completion notification
    def notify_test_completion(test_suite_result)
      return unless should_notify?(test_suite_result)
      
      notification_data = build_notification_data(test_suite_result)
      
      @enabled_notifications.each do |type|
        begin
          send_notification(type, notification_data)
          record_notification(type, notification_data)
        rescue => e
          log_error "Failed to send #{type} notification: #{e.message}"
        end
      end
    end
    
    # Send custom notification
    def notify_custom(title, message, priority: :normal, type: nil)
      notification_data = {
        title: title,
        message: message,
        priority: priority,
        timestamp: Time.now.iso8601,
        type: 'custom'
      }
      
      types_to_use = type ? [type] : @enabled_notifications
      
      types_to_use.each do |notification_type|
        begin
          send_notification(notification_type, notification_data)
          record_notification(notification_type, notification_data)
        rescue => e
          log_error "Failed to send #{notification_type} notification: #{e.message}"
        end
      end
    end
    
    # Send progress notification for long-running tests
    def notify_progress(current, total, elapsed_time, estimated_remaining = nil)
      return unless @configuration[:progress_notifications]
      
      # Only send progress notifications at certain intervals
      return unless should_send_progress_notification(current, total, elapsed_time)
      
      percentage = (current.to_f / total * 100).round(1)
      
      title = "Test Progress Update"
      message = "#{current}/#{total} tests completed (#{percentage}%)"
      
      if estimated_remaining
        message += "\nEstimated time remaining: #{format_duration(estimated_remaining)}"
      end
      
      message += "\nElapsed time: #{format_duration(elapsed_time)}"
      
      # Use only lightweight notifications for progress
      lightweight_types = @enabled_notifications & [:terminal, :file]
      
      notification_data = {
        title: title,
        message: message,
        priority: :low,
        timestamp: Time.now.iso8601,
        type: 'progress',
        progress: {
          current: current,
          total: total,
          percentage: percentage,
          elapsed: elapsed_time,
          estimated_remaining: estimated_remaining
        }
      }
      
      lightweight_types.each do |type|
        send_notification(type, notification_data)
      end
    end
    
    # Check if notifications are available
    def available_notification_types
      available = []
      
      NOTIFICATION_TYPES.each_key do |type|
        if notification_available?(type)
          available << type
        end
      end
      
      available
    end
    
    # Get notification history
    def notification_history(limit: 50)
      @notification_history.last(limit)
    end
    
    # Clear notification history
    def clear_history
      @notification_history.clear
      log_debug "Notification history cleared"
    end
    
    private
    
    def determine_enabled_notifications
      # Check configuration first
      if @configuration[:enabled_types]
        enabled = @configuration[:enabled_types]
      else
        # Auto-detect available notification methods
        enabled = available_notification_types
      end
      
      # Ensure at least terminal notifications are enabled
      enabled << :terminal unless enabled.include?(:terminal)
      
      enabled.uniq
    end
    
    def notification_available?(type)
      case type
      when :desktop
        desktop_notification_available?
      when :terminal
        true # Always available
      when :webhook
        @configuration[:webhook_url].present?
      when :email
        email_configuration_valid?
      when :slack
        @configuration[:slack_webhook_url].present?
      when :file
        true # Always available
      else
        false
      end
    end
    
    def desktop_notification_available?
      # Check for macOS
      return true if system("which osascript > /dev/null 2>&1")
      
      # Check for Linux desktop notification tools
      return true if system("which notify-send > /dev/null 2>&1")
      return true if system("which kdialog > /dev/null 2>&1")
      return true if system("which zenity > /dev/null 2>&1")
      
      false
    end
    
    def email_configuration_valid?
      @configuration[:email] &&
        @configuration[:email][:smtp_server] &&
        @configuration[:email][:from_address] &&
        @configuration[:email][:to_addresses]
    end
    
    def should_notify?(test_suite_result)
      # Check notification conditions
      min_duration = @configuration[:min_duration_for_notification] || 30
      return false if test_suite_result.total_duration < min_duration
      
      # Check if we should notify on success
      if test_suite_result.success?
        return @configuration[:notify_on_success] != false
      else
        return @configuration[:notify_on_failure] != false
      end
    end
    
    def should_send_progress_notification(current, total, elapsed_time)
      # Send at 25%, 50%, 75% completion
      percentage = (current.to_f / total * 100).round
      milestones = [25, 50, 75]
      
      return true if milestones.include?(percentage)
      
      # Send every 5 minutes for long-running tests
      return true if elapsed_time > 300 && (elapsed_time % 300) < 10
      
      false
    end
    
    def build_notification_data(test_suite_result)
      title = if test_suite_result.success?
                "✅ Mitamae Tests Completed Successfully"
              else
                "❌ Mitamae Tests Failed"
              end
      
      summary = test_suite_result.summary
      message = <<~MESSAGE
        Test Suite: #{test_suite_result.name || 'Default Suite'}
        Total Tests: #{summary[:total]}
        Passed: #{summary[:passed]}
        Failed: #{summary[:failed]}
        Duration: #{format_duration(test_suite_result.total_duration)}
        Pass Rate: #{summary[:pass_rate]}%
      MESSAGE
      
      if test_suite_result.failed_tests.any?
        message += "\nFailed Tests:\n"
        test_suite_result.failed_tests.first(5).each do |test|
          message += "• #{test.name}\n"
        end
        
        if test_suite_result.failed_tests.length > 5
          message += "• ... and #{test_suite_result.failed_tests.length - 5} more\n"
        end
      end
      
      {
        title: title,
        message: message.strip,
        priority: test_suite_result.success? ? :normal : :high,
        timestamp: Time.now.iso8601,
        type: 'test_completion',
        test_result: {
          success: test_suite_result.success?,
          total: summary[:total],
          passed: summary[:passed],
          failed: summary[:failed],
          duration: test_suite_result.total_duration,
          pass_rate: summary[:pass_rate]
        }
      }
    end
    
    def send_notification(type, notification_data)
      case type
      when :desktop
        send_desktop_notification(notification_data)
      when :terminal
        send_terminal_notification(notification_data)
      when :webhook
        send_webhook_notification(notification_data)
      when :email
        send_email_notification(notification_data)
      when :slack
        send_slack_notification(notification_data)
      when :file
        send_file_notification(notification_data)
      end
    end
    
    def send_desktop_notification(notification_data)
      title = notification_data[:title]
      message = notification_data[:message]
      
      if system("which osascript > /dev/null 2>&1") # macOS
        # Use AppleScript for macOS notifications
        script = <<~APPLESCRIPT
          display notification "#{message.gsub('"', '\"')}" with title "#{title.gsub('"', '\"')}"
        APPLESCRIPT
        
        system("osascript -e '#{script}'")
        
      elsif system("which notify-send > /dev/null 2>&1") # Linux
        urgency = case notification_data[:priority]
                  when :high then 'critical'
                  when :low then 'low'
                  else 'normal'
                  end
        
        system("notify-send --urgency=#{urgency} '#{title}' '#{message}'")
        
      elsif system("which kdialog > /dev/null 2>&1") # KDE
        system("kdialog --passivepopup '#{message}' 10 --title '#{title}'")
        
      elsif system("which zenity > /dev/null 2>&1") # GNOME
        system("zenity --notification --text='#{title}: #{message}'")
        
      else
        log_warn "No desktop notification method available"
      end
    end
    
    def send_terminal_notification(notification_data)
      # Terminal bell
      print "\a" if @configuration[:terminal_bell] != false
      
      # Status message
      puts "\n" + "="*60
      puts "🔔 NOTIFICATION: #{notification_data[:title]}"
      puts "="*60
      puts notification_data[:message]
      puts "="*60
      
      # Update terminal title if supported
      if ENV['TERM'] && !ENV['TERM'].include?('dumb')
        title = "Mitamae Tests: #{notification_data[:test_result][:success] ? 'PASSED' : 'FAILED'}"
        print "\033]0;#{title}\007"
      end
    end
    
    def send_webhook_notification(notification_data)
      webhook_url = @configuration[:webhook_url]
      return unless webhook_url
      
      payload = {
        notification: notification_data,
        source: 'mitamae-test-framework',
        timestamp: notification_data[:timestamp]
      }
      
      # Use curl to send webhook (most portable option)
      curl_command = [
        'curl',
        '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-d', JSON.generate(payload),
        '--max-time', '10',
        '--silent',
        webhook_url
      ]
      
      system(*curl_command)
    end
    
    def send_email_notification(notification_data)
      return unless email_configuration_valid?
      
      email_config = @configuration[:email]
      
      # Create email content
      subject = notification_data[:title]
      body = notification_data[:message]
      
      # Use system mail command if available
      if system("which mail > /dev/null 2>&1")
        email_config[:to_addresses].each do |to_address|
          mail_command = "echo '#{body}' | mail -s '#{subject}' #{to_address}"
          system(mail_command)
        end
      else
        log_warn "Mail command not available for email notifications"
      end
    end
    
    def send_slack_notification(notification_data)
      slack_url = @configuration[:slack_webhook_url]
      return unless slack_url
      
      # Format message for Slack
      color = case notification_data[:priority]
              when :high then 'danger'
              when :low then '#439FE0'
              else 'good'
              end
      
      payload = {
        text: notification_data[:title],
        attachments: [
          {
            color: color,
            text: notification_data[:message],
            ts: Time.now.to_i
          }
        ]
      }
      
      # Send to Slack
      curl_command = [
        'curl',
        '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-d', JSON.generate(payload),
        '--max-time', '10',
        '--silent',
        slack_url
      ]
      
      system(*curl_command)
    end
    
    def send_file_notification(notification_data)
      notification_file = @configuration[:notification_file] || '/tmp/mitamae_test_notifications.txt'
      
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      entry = <<~ENTRY
        [#{timestamp}] #{notification_data[:title]}
        #{notification_data[:message]}
        ---
      ENTRY
      
      File.open(notification_file, 'a') do |f|
        f.write(entry)
      end
      
      # Keep file size reasonable
      if File.size(notification_file) > 1_000_000 # 1MB
        lines = File.readlines(notification_file)
        File.write(notification_file, lines.last(100).join)
      end
    end
    
    def record_notification(type, notification_data)
      record = {
        type: type,
        timestamp: Time.now.iso8601,
        notification: notification_data
      }
      
      @notification_history << record
      
      # Keep history size reasonable
      @notification_history = @notification_history.last(1000) if @notification_history.length > 1000
      
      log_debug "Recorded #{type} notification: #{notification_data[:title]}"
    end
    
    def format_duration(seconds)
      return "#{seconds}s" if seconds < 60
      
      minutes = seconds / 60
      remaining_seconds = seconds % 60
      
      if minutes < 60
        "#{minutes}m #{remaining_seconds}s"
      else
        hours = minutes / 60
        remaining_minutes = minutes % 60
        "#{hours}h #{remaining_minutes}m"
      end
    end
    
    # Extension methods for integrating with test runner
    def self.setup_for_test_suite(test_suite, configuration = {})
      notification_system = new(configuration)
      
      # Hook into test suite events
      test_suite.define_singleton_method(:notification_system) { notification_system }
      
      # Add progress notification callback
      if configuration[:progress_notifications]
        test_suite.on_test_completed do |current_count, total_count, elapsed_time|
          estimated_remaining = if current_count > 0
                                  (elapsed_time / current_count) * (total_count - current_count)
                                else
                                  nil
                                end
          
          notification_system.notify_progress(current_count, total_count, elapsed_time, estimated_remaining)
        end
      end
      
      # Add completion notification callback
      test_suite.on_suite_completed do |suite_result|
        notification_system.notify_test_completion(suite_result)
      end
      
      notification_system
    end
  end
  
  # Configuration helper for common notification setups
  class NotificationConfiguration
    def self.development_config
      {
        enabled_types: [:terminal, :desktop],
        min_duration_for_notification: 10,
        notify_on_success: true,
        notify_on_failure: true,
        progress_notifications: false,
        terminal_bell: true
      }
    end
    
    def self.ci_config
      {
        enabled_types: [:webhook, :file],
        min_duration_for_notification: 0,
        notify_on_success: true,
        notify_on_failure: true,
        progress_notifications: true,
        notification_file: '/tmp/ci_test_notifications.txt'
      }
    end
    
    def self.team_config(slack_webhook_url, email_addresses = [])
      {
        enabled_types: [:desktop, :slack, :email],
        min_duration_for_notification: 60,
        notify_on_success: false,
        notify_on_failure: true,
        progress_notifications: false,
        slack_webhook_url: slack_webhook_url,
        email: {
          to_addresses: email_addresses
        }
      }
    end
    
    def self.silent_config
      {
        enabled_types: [:file],
        min_duration_for_notification: 0,
        notify_on_success: false,
        notify_on_failure: true,
        notification_file: '/tmp/mitamae_test_silent.txt'
      }
    end
  end
end