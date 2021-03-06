# FedEx module by Jimmy Baker
# http://github.com/jimmyebaker

module ActiveMerchant
  module Shipping
    
    # :key is your developer API key
    # :password is your API password
    # :account is your FedEx account number
    # :login is your meter number
    class FedEx < Carrier
      class BadResponseError < StandardError; end
      
      self.retry_safe = true
      
      cattr_reader :name
      @@name = "FedEx"
      
      TEST_URL = 'https://gatewaybeta.fedex.com:443/xml'
      LIVE_URL = 'https://gateway.fedex.com:443/xml'
      
      CarrierCodes = {
        "fedex_ground" => "FDXG",
        "fedex_express" => "FDXE"
      }
      
      ServiceTypes = {
        "PRIORITY_OVERNIGHT" => "FedEx Priority Overnight",
        "PRIORITY_OVERNIGHT_SATURDAY_DELIVERY" => "FedEx Priority Overnight Saturday Delivery",
        "FEDEX_2_DAY" => "FedEx 2 Day",
        "FEDEX_2_DAY_SATURDAY_DELIVERY" => "FedEx 2 Day Saturday Delivery",
        "STANDARD_OVERNIGHT" => "FedEx Standard Overnight",
        "FIRST_OVERNIGHT" => "FedEx First Overnight",
        "FIRST_OVERNIGHT_SATURDAY_DELIVERY" => "FedEx First Overnight Saturday Delivery",
        "FEDEX_EXPRESS_SAVER" => "FedEx Express Saver",
        "FEDEX_1_DAY_FREIGHT" => "FedEx 1 Day Freight",
        "FEDEX_1_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 1 Day Freight Saturday Delivery",
        "FEDEX_2_DAY_FREIGHT" => "FedEx 2 Day Freight",
        "FEDEX_2_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 2 Day Freight Saturday Delivery",
        "FEDEX_3_DAY_FREIGHT" => "FedEx 3 Day Freight",
        "FEDEX_3_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 3 Day Freight Saturday Delivery",
        "INTERNATIONAL_PRIORITY" => "FedEx International Priority",
        "INTERNATIONAL_PRIORITY_SATURDAY_DELIVERY" => "FedEx International Priority Saturday Delivery",
        "INTERNATIONAL_ECONOMY" => "FedEx International Economy",
        "INTERNATIONAL_FIRST" => "FedEx International First",
        "INTERNATIONAL_PRIORITY_FREIGHT" => "FedEx International Priority Freight",
        "INTERNATIONAL_ECONOMY_FREIGHT" => "FedEx International Economy Freight",
        "GROUND_HOME_DELIVERY" => "FedEx Ground Home Delivery",
        "FEDEX_GROUND" => "FedEx Ground",
        "INTERNATIONAL_GROUND" => "FedEx International Ground"
      }

      PackageTypes = {
        "fedex_envelope" => "FEDEX_ENVELOPE",
        "fedex_pak" => "FEDEX_PAK",
        "fedex_box" => "FEDEX_BOX",
        "fedex_tube" => "FEDEX_TUBE",
        "fedex_10_kg_box" => "FEDEX_10KG_BOX",
        "fedex_25_kg_box" => "FEDEX_25KG_BOX",
        "your_packaging" => "YOUR_PACKAGING"
      }

      DropoffTypes = {
        'regular_pickup' => 'REGULAR_PICKUP',
        'request_courier' => 'REQUEST_COURIER',
        'dropbox' => 'DROP_BOX',
        'business_service_center' => 'BUSINESS_SERVICE_CENTER',
        'station' => 'STATION'
      }

      PaymentTypes = {
        'sender' => 'SENDER',
        'recipient' => 'RECIPIENT',
        'third_party' => 'THIRDPARTY',
        'collect' => 'COLLECT'
      }
      
      PackageIdentifierTypes = {
        'tracking_number' => 'TRACKING_NUMBER_OR_DOORTAG',
        'door_tag' => 'TRACKING_NUMBER_OR_DOORTAG',
        'rma' => 'RMA',
        'ground_shipment_id' => 'GROUND_SHIPMENT_ID',
        'ground_invoice_number' => 'GROUND_INVOICE_NUMBER',
        'ground_customer_reference' => 'GROUND_CUSTOMER_REFERENCE',
        'ground_po' => 'GROUND_PO',
        'express_reference' => 'EXPRESS_REFERENCE',
        'express_mps_master' => 'EXPRESS_MPS_MASTER'
      }

      def self.service_name_for_code(service_code)
        ServiceTypes[service_code] || begin
          name = service_code.downcase.split('_').collect{|word| word.capitalize }.join(' ')
          "FedEx #{name.sub(/Fedex /, '')}"
        end
      end
      
      def requirements
        [:key, :password, :account, :login]
      end
      
      def find_rates(origin, destination, packages, options = {})
        options = @options.update(options)
        packages = Array(packages)
        
        rate_request = build_rate_request(origin, destination, packages, options)
        
        response = commit(save_request(rate_request), (options[:test] || false)).gsub(/<(\/)?.*?\:(.*?)>/, '<\1\2>')
        
        parse_rate_response(origin, destination, packages, response, options)
      end
      
      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(save_request(tracking_request), (options[:test] || false)).gsub(/<(\/)?.*?\:(.*?)>/, '<\1\2>')
        parse_tracking_response(response, options)
      end

      def verify_address(address, options = {})
        options = @options.update(options)
         
        address_verification_request = build_address_verification_request(address, options)
        
        response = commit(save_request(address_verification_request), false)
        parse_address_verification_response(response)
      end
      
      protected
      def build_rate_request(origin, destination, packages, options={})
        imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))

        xml_request = XmlNode.new('RateRequest', 'xmlns' => 'http://fedex.com/ws/rate/v6') do |root_node|
          root_node << build_request_header

          # Version
          root_node << XmlNode.new('Version') do |version_node|
            version_node << XmlNode.new('ServiceId', 'crs')
            version_node << XmlNode.new('Major', '6')
            version_node << XmlNode.new('Intermediate', '0')
            version_node << XmlNode.new('Minor', '0')
          end
          
          # Returns delivery dates
          root_node << XmlNode.new('ReturnTransitAndCommit', true)
          # Returns saturday delivery shipping options when available
          root_node << XmlNode.new('VariableOptions', 'SATURDAY_DELIVERY')
          
          root_node << XmlNode.new('RequestedShipment') do |rs|
            rs << XmlNode.new('ShipTimestamp', Time.now)
            rs << XmlNode.new('DropoffType', options[:dropoff_type] || 'REGULAR_PICKUP')
            rs << XmlNode.new('PackagingType', options[:packaging_type] || 'YOUR_PACKAGING')
            
            rs << build_location_node('Shipper', (options[:shipper] || origin))
            rs << build_location_node('Recipient', destination)
            if options[:shipper] and options[:shipper] != origin
              rs << build_location_node('Origin', origin)
            end
            
            rs << XmlNode.new('RateRequestTypes', 'ACCOUNT')
            rs << XmlNode.new('PackageCount', packages.size)
            packages.each do |pkg|
              rs << XmlNode.new('RequestedPackages') do |rps|
                rps << XmlNode.new('Weight') do |tw|
                  tw << XmlNode.new('Units', imperial ? 'LB' : 'KG')
                  tw << XmlNode.new('Value', [((imperial ? pkg.lbs : pkg.kgs).to_f*1000).round/1000.0, 0.1].max)
                end
                rps << XmlNode.new('Dimensions') do |dimensions|
                  [:length,:width,:height].each do |axis|
                    value = ((imperial ? pkg.inches(axis) : pkg.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                    dimensions << XmlNode.new(axis.to_s.capitalize, value.ceil)
                  end
                  dimensions << XmlNode.new('Units', imperial ? 'IN' : 'CM')
                end
              end
            end
            
          end
        end
        xml_request.to_s
      end

      def build_address_verification_request(address,options={})
        is_residential = !! options[:residential]
        root_node = XmlNode.new("AddressValidationRequest",
          'xmlns' => "http://fedex.com/ws/addressvalidation/v2",
          'xmlns:xsd'  => "http://www.w3.org/2001/XMLSchema",
          'xmlns:soap' => "http://schemas.xmlsoap.org/soap/envelope/", 
          'xmlns:xsi'  => "http://www.w3.org/2001/XMLSchema-instance",
          'xmlns:rep'  => "http://fedex.com/esb/report") do |root_node|
          root_node << build_request_header
          
          root_node << XmlNode.new("Version") do |version_node|
            version_node << XmlNode.new("ServiceId", 'aval')
            version_node << XmlNode.new("Major", '2')
            version_node << XmlNode.new("Intermediate", '0')
            version_node << XmlNode.new("Minor", '0')
          end
          
          root_node << XmlNode.new("RequestTimestamp", Time.now)
          
          root_node << XmlNode.new("Options") do |options_node|
            options_node << XmlNode.new("CheckResidentialStatus", 1)
            options_node << XmlNode.new("MaximumNumberOfMatches", 5)
            options_node << XmlNode.new("StreetAccuracy", 'LOOSE')
            options_node << XmlNode.new("DirectionalAccuracy", 'LOOSE')
            options_node << XmlNode.new("CompanyNameAccuracy", 'LOOSE')
            options_node << XmlNode.new("RecognizeAlternateCityNames", "true")
            options_node << XmlNode.new("ReturnParsedElements", "true")
          end
          
          
          root_node << XmlNode.new("AddressesToValidate") do |addrs_node|
            addrs_node << XmlNode.new("AddressId",   'first')
            addrs_node << XmlNode.new("Address") do |addr_node|
              addr_node << XmlNode.new("StreetLines", [address.address1, address.address2, address.address3].join("\n"))
              addr_node << XmlNode.new("City", address.city)
              addr_node << XmlNode.new("StateOrProvinceCode", address.state)
              addr_node << XmlNode.new("PostalCode", address.postal_code)
              addr_node << XmlNode.new("CountryCode", address.country_code)
              addr_node << XmlNode.new("Residential", is_residential)
            end
          end
        end
        
        root_node.to_s
      end
      
      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest', 'xmlns' => 'http://fedex.com/ws/track/v3') do |root_node|
          root_node << build_request_header
          
          # Version
          root_node << XmlNode.new('Version') do |version_node|
            version_node << XmlNode.new('ServiceId', 'trck')
            version_node << XmlNode.new('Major', '3')
            version_node << XmlNode.new('Intermediate', '0')
            version_node << XmlNode.new('Minor', '0')
          end
          
          root_node << XmlNode.new('PackageIdentifier') do |package_node|
            package_node << XmlNode.new('Value', tracking_number)
            package_node << XmlNode.new('Type', PackageIdentifierTypes[options['package_identifier_type'] || 'tracking_number'])
          end
          
          root_node << XmlNode.new('ShipDateRangeBegin', options['ship_date_range_begin']) if options['ship_date_range_begin']
          root_node << XmlNode.new('ShipDateRangeEnd', options['ship_date_range_end']) if options['ship_date_range_end']
          root_node << XmlNode.new('IncludeDetailedScans', 1)
        end
        xml_request.to_s
      end
    
     
      def build_request_header()
        web_authentication_detail = XmlNode.new('WebAuthenticationDetail') do |wad|
          wad << XmlNode.new('UserCredential') do |uc|
            uc << XmlNode.new('Key', @options[:key])
            uc << XmlNode.new('Password', @options[:password])
          end
        end
        
        client_detail = XmlNode.new('ClientDetail') do |cd|
          cd << XmlNode.new('AccountNumber', @options[:account])
          cd << XmlNode.new('MeterNumber', @options[:login])
        end
        
        trasaction_detail = XmlNode.new('TransactionDetail') do |td|
          td << XmlNode.new('CustomerTransactionId', 'ActiveShipping') # TODO: Need to do something better with this..
        end
        
        [web_authentication_detail, client_detail, trasaction_detail]
      end
            
      def build_location_node(name, location)
        location_node = XmlNode.new(name) do |xml_node|
          xml_node << XmlNode.new('Address') do |address_node|
            address_node << XmlNode.new('City', location.city)
            address_node << XmlNode.new('StateOrProvinceCode', location.state)
            address_node << XmlNode.new('PostalCode', location.postal_code)
            address_node << XmlNode.new("CountryCode", location.country_code(:alpha2))
            address_node << XmlNode.new('Residential', 'true') if location.address_type == 'residential'
          end
        end
      end
      
      def parse_rate_response(origin, destination, packages, response, options)
        rate_estimates = []
        success, message = nil
        
        xml = REXML::Document.new(response)
        root_node = xml.elements['RateReply']
        
        success = response_success?(xml)
        message = response_message(xml)
        
        root_node.elements.each('RateReplyDetails') do |rated_shipment|
          service_code = rated_shipment.get_text('ServiceType').to_s
          is_saturday_delivery = rated_shipment.get_text('AppliedOptions').to_s == 'SATURDAY_DELIVERY'
          service_type = is_saturday_delivery ? "#{service_code}_SATURDAY_DELIVERY" : service_code
          
          rate_estimates << RateEstimate.new(origin, destination, @@name,
                              self.class.service_name_for_code(service_type),
                              :service_code => service_code,
                              :service_type => service_type,
                              :total_price => rated_shipment.get_text('RatedShipmentDetails/ShipmentRateDetail/TotalNetCharge/Amount').to_s.to_f,
                              :currency => rated_shipment.get_text('RatedShipmentDetails/ShipmentRateDetail/TotalNetCharge/Currency').to_s,
                              :packages => packages,
                              :delivery_date => rated_shipment.get_text('DeliveryTimestamp').to_s)
        end
		
        if rate_estimates.empty?
          success = false
          message = "No shipping rates could be found for the destination address" if message.blank?
        end
        
        RateResponse.new(success, message, Hash.from_xml(response), :rates => rate_estimates, :xml => response, :request => last_request, :log_xml => options[:log_xml])
      end
      
      def parse_address_verification_response(response)
        ns = "v2"
        nsp = "#{ns}:"
        xml = REXML::Document.new(response)
        root_node = xml.elements["#{nsp}AddressValidationReply"]
         
        success = response_success?(xml,ns)
        message = response_message(xml,ns)
         
        addresses = []
        e_results = xml.elements["/*/#{nsp}AddressResults"]
        
        results = e_results[1..-1].map do |e_details|
          score = e_details.elements["#{nsp}Score"].text.to_i
          
          e_res_status    = e_details.elements["#{nsp}ResidentialStatus"]
          fedex_addr_type = e_res_status ? e_res_status.text : nil
          address_type = {'RESIDENTIAL' => 'residential',
                          'BUSINESS'    => 'commercial'}[fedex_addr_type]
           
          e_addr = e_details.elements["#{nsp}Address"] 
          
          raise BadResponseError if e_addr.children.empty?
          
          location = Location.new(
            :address1     => lambda {e_addr.elements["#{nsp}StreetLines"].text.to_s rescue ""}.call,
            :city         => lambda {e_addr.elements["#{nsp}City"].text.to_s rescue ""}.call,
            :province     => lambda {e_addr.elements["#{nsp}StateOrProvinceCode"].text.to_s rescue ""}.call,
            :postal_code  => lambda {e_addr.elements["#{nsp}PostalCode"].text.to_s rescue ""}.call,
            :country      => lambda {e_addr.elements["#{nsp}CountryCode"].text.to_s rescue ""}.call,
            :address_type => address_type
          )
          
          {:score => score, :location => location}
        end
        
        results
      end
      
      def parse_tracking_response(response, options)
        xml = REXML::Document.new(response)
        root_node = xml.elements['TrackReply']
        
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          tracking_number, origin, destination = nil
          shipment_events = []
          
          tracking_details = root_node.elements['TrackDetails']
          tracking_number = tracking_details.get_text('TrackingNumber').to_s
          
          destination_node = tracking_details.elements['DestinationAddress']
          destination = Location.new(
                :country =>     destination_node.get_text('CountryCode').to_s,
                :province =>    destination_node.get_text('StateOrProvinceCode').to_s,
                :city =>        destination_node.get_text('City').to_s
              )
          
          tracking_details.elements.each('Events') do |event|
            l_attrs = {
              :city => event.elements['Address'].get_text('City').to_s,
              :state => event.elements['Address'].get_text('StateOrProvinceCode').to_s,
              :postal_code => event.elements['Address'].get_text('PostalCode').to_s,
              :country => event.elements['Address'].get_text('CountryCode').to_s
            }
            next unless l_attrs['postal_code'] && l_attrs['country']
            location = Location.new(l_attrs)

            description = event.get_text('EventDescription').to_s
            
            # for now, just assume UTC, even though it probably isn't
            time = Time.parse("#{event.get_text('Timestamp').to_s}")
            zoneless_time = Time.utc(time.year, time.month, time.mday, time.hour, time.min, time.sec)
            
            shipment_events << ShipmentEvent.new(description, zoneless_time, location)
          end
          shipment_events = shipment_events.sort_by(&:time)
        end
        
        TrackingResponse.new(success, message, Hash.from_xml(response),
          :xml => response,
          :request => last_request,
          :shipment_events => shipment_events,
          :destination => destination,
          :tracking_number => tracking_number
        )
      end
            
      def response_status_node(document,ns='')
        ns = "#{ns}:" unless ns.empty?
        document.elements["/*/#{ns}Notifications/"]
      end
      
      def response_success?(document,ns='')
        response_node = response_status_node(document,ns)
        ns = "#{ns}:" unless ns.empty?
        %w{SUCCESS WARNING NOTE}.include? response_node.get_text("#{ns}Severity").to_s
      end
      
      def response_message(document,ns='')
        response_node = response_status_node(document,ns)
        ns = "#{ns}:" unless ns.empty?
        "#{response_node.get_text("#{ns}Severity").to_s} - #{response_node.get_text("#{ns}Code").to_s}: #{response_node.get_text("#{ns}Message").to_s}"
      end
      
      def commit(request, test = false)
        ssl_post(test ? TEST_URL : LIVE_URL, request.gsub("\n",''))        
      end
    
    end
  end
end
