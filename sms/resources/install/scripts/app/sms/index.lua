--	sms.lua
--	Part of FusionPBX
--	Copyright (C) 2010 Mark J Crane <markjcrane@fusionpbx.com>
--	All rights reserved.
--
--	Redistribution and use in source and binary forms, with or without
--	modification, are permitted provided that the following conditions are met:
--
--	1. Redistributions of source code must retain the above copyright notice,
--	   this list of conditions and the following disclaimer.
--
--	2. Redistributions in binary form must reproduce the above copyright
--	   notice, this list of conditions and the following disclaimer in the
--	   documentation and/or other materials provided with the distribution.
--
--	THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
--	INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
--	AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
--	AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
--	OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
--	SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
--	INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
--	CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
--	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
--	POSSIBILITY OF SUCH DAMAGE.

--connect to the database
	require "resources.functions.database_handle";
	dbh = database_handle('system');

--debug
	debug["info"] = false;
	debug["sql"] = false;

--set the api
	api = freeswitch.API();

--define uuid function
	local random = math.random;
	local function uuid()
		local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
		return string.gsub(template, '[xy]', function (c)
			local v = (c == 'x') and random(0, 0xf) or random(8, 0xb);
			return string.format('%x', v);
		end)
	end

--get the argv values
	script_name = argv[0];
	direction = argv[2];
	
	if (debug["info"]) then
		freeswitch.consoleLog("notice", "[sms] DIRECTION: " .. direction .. "\n");
		freeswitch.consoleLog("info", "chat console\n");
	end
	
	if direction == "inbound" then
		to = argv[3];
		from = argv[4];
		body = argv[5];
		domain_name = string.match(to,'%@+(.+)');
		extension = string.match(to,'%d+');

		if (debug["info"]) then
			freeswitch.consoleLog("notice", "[sms] DIRECTION: " .. direction .. "\n");
			freeswitch.consoleLog("notice", "[sms] TO: " .. to .. "\n");
			freeswitch.consoleLog("notice", "[sms] Extension: " .. extension .. "\n");
			freeswitch.consoleLog("notice", "[sms] FROM: " .. from .. "\n");
			freeswitch.consoleLog("notice", "[sms] BODY: " .. body .. "\n");
			freeswitch.consoleLog("notice", "[sms] DOMAIN_NAME: " .. domain_name .. "\n");
		end

		local event = freeswitch.Event("CUSTOM", "SMS::SEND_MESSAGE");
		event:addHeader("proto", "sip");
		event:addHeader("dest_proto", "sip");
		event:addHeader("from", "sip:" .. from);
		event:addHeader("from_full", "sip:" .. from);
		event:addHeader("sip_profile","internal");
		event:addHeader("to", to);
		event:addHeader("subject", "sip:" .. to);
		event:addHeader("type", "text/html");
		event:addHeader("hint", "the hint");
		event:addHeader("replying", "true");
		event:addBody(body);

		if (debug["info"]) then
			freeswitch.consoleLog("info", event:serialize());
		end
		event:fire();
		to = extension;
	elseif direction == "outbound" then
		if (argv[3] ~= nil) then
			to_user = argv[3];
			to = string.match(to_user,'%d+');
		else 
			to = message:getHeader("to_user");
		end
		if (argv[3] ~= nil) then
			domain_name = string.match(to_user,'%@+(.+)');
		else
			domain_name = message:getHeader("from_host");
		end
		if (argv[4] ~= nil) then
			from = argv[4];
			extension = string.match(from,'%d+');
			if extension:len() > 7 then
				outbound_caller_id_number = extension;
			end 
		else
			from = message:getHeader("from_user");
		end
		if (argv[5] ~= nil) then
			body = argv[5];
		else
			body = message:getBody();
		end

		if (debug["info"]) then
			if (message ~= nil) then
				freeswitch.consoleLog("info", message:serialize());
			end
			freeswitch.consoleLog("notice", "[sms] DIRECTION: " .. direction .. "\n");
			freeswitch.consoleLog("notice", "[sms] TO: " .. to .. "\n");
			freeswitch.consoleLog("notice", "[sms] FROM: " .. from .. "\n");
			freeswitch.consoleLog("notice", "[sms] BODY: " .. body .. "\n");
			freeswitch.consoleLog("notice", "[sms] DOMAIN_NAME: " .. domain_name .. "\n");
		end
		
		if (domain_uuid == nil) then
			--get the domain_uuid using the domain name required for multi-tenant
				if (domain_name ~= nil) then
					sql = "SELECT domain_uuid FROM v_domains ";
					sql = sql .. "WHERE domain_name = '" .. domain_name .. "' and domain_enabled = 'true' ";
					if (debug["sql"]) then
						freeswitch.consoleLog("notice", "[voicemail] SQL: " .. sql .. "\n");
					end
					status = dbh:query(sql, function(rows)
						domain_uuid = rows["domain_uuid"];
					end);
				end
		end
		freeswitch.consoleLog("notice", "[sms] DOMAIN_UUID: " .. domain_uuid .. "\n");
		if (outbound_caller_id_number == nil) then
			--get the outbound_caller_id_number using the domain_uuid and the extension number
				if (domain_uuid ~= nil) then
					sql = "SELECT outbound_caller_id_number, extension_uuid, carrier FROM v_extensions ";
					sql = sql .. ", v_sms_destinations ";
					sql = sql .. "WHERE outbound_caller_id_number = destination and  ";
					sql = sql .. "v_extensions.domain_uuid = '" .. domain_uuid .. "' and extension = '" .. from .."' and ";
					sql = sql .. "v_sms_destinations.enabled = 'true' and ";
					sql = sql .. "v_extensions.enabled = 'true'";

					if (debug["sql"]) then
						freeswitch.consoleLog("notice", "[sms] SQL: " .. sql .. "\n");
					end
					status = dbh:query(sql, function(rows)
						outbound_caller_id_number = rows["outbound_caller_id_number"];
						extension_uuid = rows["extension_uuid"];
						carrier = rows["carrier"];
					end);
				end
		elseif (outbound_caller_id_number ~= nil) then
			--get the outbound_caller_id_number using the domain_uuid and the extension number
				if (domain_uuid ~= nil) then
					sql = "SELECT carrier FROM  ";
					sql = sql .. " v_sms_destinations ";
					sql = sql .. "WHERE destination = '" .. from .. "' and ";
					sql = sql .. "v_sms_destinations.domain_uuid = '" .. domain_uuid .. "' and ";
					sql = sql .. "enabled = 'true'";
					if (debug["sql"]) then
						freeswitch.consoleLog("notice", "[sms] SQL: " .. sql .. "\n");
					end
					status = dbh:query(sql, function(rows)
						carrier = rows["carrier"];
					end);
				end
		end
		
		sql = "SELECT default_setting_value FROM v_default_settings ";
		sql = sql .. "where default_setting_category = 'sms' and default_setting_subcategory = '" .. carrier .. "_access_key'";
		if (debug["sql"]) then
			freeswitch.consoleLog("notice", "[sms] SQL: " .. sql .. "\n");
		end
		status = dbh:query(sql, function(rows)
			access_key = rows["default_setting_value"];
		end);

		sql = "SELECT default_setting_value FROM v_default_settings ";
		sql = sql .. "where default_setting_category = 'sms' and default_setting_subcategory = '" .. carrier .. "_secret_key'";
		if (debug["sql"]) then
			freeswitch.consoleLog("notice", "[sms] SQL: " .. sql .. "\n");
		end
		status = dbh:query(sql, function(rows)
			secret_key = rows["default_setting_value"];
		end);

		sql = "SELECT default_setting_value FROM v_default_settings ";
		sql = sql .. "where default_setting_category = 'sms' and default_setting_subcategory = '" .. carrier .. "_api_url'";
		if (debug["sql"]) then
			freeswitch.consoleLog("notice", "[sms] SQL: " .. sql .. "\n");
		end
		status = dbh:query(sql, function(rows)
			api_url = rows["default_setting_value"];
		end);

		if (carrier == "flowroute") then
			cmd = "curl -u ".. access_key ..":" .. secret_key .. " -H \"Content-Type: application/json\" -X POST -d '{\"to\":\"" .. to .. "\",\"from\":\"" .. outbound_caller_id_number .."\",\"body\":\"" .. body .. "\"}' " .. api_url;
		elseif (carrier == "twilio") then
			if to:len() < 11 then
				to = "1" .. to;
			end
			if outbound_caller_id_number:len() < 11 then
				outbound_caller_id_number = "1" .. outbound_caller_id_number;
			end
		-- Can be either +1NANNNNXXXX or NANNNNXXXX
			cmd ="curl -X POST '" .. api_url .."' --data-urlencode 'To=+" .. to .."' --data-urlencode 'From=+" .. outbound_caller_id_number .. "' --data-urlencode 'Body=" .. body .. "' -u ".. access_key ..":" .. secret_key .. " --insecure";
		elseif (carrier == "teli") then
			cmd ="curl -X POST '" .. api_url .."' --data-urlencode 'destination=" .. to .."' --data-urlencode 'source=" .. outbound_caller_id_number .. "' --data-urlencode 'message=" .. body .. "' --data-urlencode 'token=" .. access_key .. "' --insecure";
		elseif (carrier == "plivo") then
			if to:len() <11 then
				to = "1"..to;
			end
			cmd="curl -i --user " .. access_key .. ":" .. secret_key .. " -H \"Content-Type: application/json\" -d '{\"src\": \"" .. outbound_caller_id_number .. "\",\"dst\": \"" .. to .."\", \"text\": \"" .. body .. "\"}' " .. api_url;
		end
		if (debug["info"]) then
			freeswitch.consoleLog("notice", "[sms] CMD: " .. cmd .. "\n");
		end
		local handle = io.popen(cmd)
		local result = handle:read("*a")
		handle:close()
		if (debug["info"]) then
			freeswitch.consoleLog("notice", "[sms] CURL Returns: " .. result .. "\n");
		end
--		os.execute(cmd)

	end
	
--write message to DB

	if (domain_uuid == nil) then
		--get the domain_uuid using the domain name required for multi-tenant
			if (domain_name ~= nil) then
				sql = "SELECT domain_uuid FROM v_domains ";
				sql = sql .. "WHERE domain_name = '" .. domain_name .. "' ";
				if (debug["sql"]) then
					freeswitch.consoleLog("notice", "[voicemail] SQL: " .. sql .. "\n");
				end
				status = dbh:query(sql, function(rows)
					domain_uuid = rows["domain_uuid"];
				end);
			end
	end
	if (extension_uuid == nil) then
		--get the extension_uuid using the domain_uuid and the extension number
			if (domain_uuid ~= nil) then
				sql = "SELECT extension_uuid FROM v_extensions ";
				sql = sql .. "WHERE domain_uuid = '" .. domain_uuid .. "' and extension = '" .. extension .."' ";
				if (debug["sql"]) then
					freeswitch.consoleLog("notice", "[sms] SQL EXTENSION: " .. sql .. "\n");
				end
				status = dbh:query(sql, function(rows)
					extension_uuid = rows["extension_uuid"];
				end);
			end
	end
	if (carrier == nil) then
		carrier = '';
	end


	if (extension_uuid ~= nil) then
		sql = "insert into v_sms_messages";
		sql = sql .. "(sms_message_uuid,extension_uuid,domain_uuid,start_stamp,from_number,to_number,message,direction,response,carrier)";
		sql = sql .. " values ('" .. uuid() .. "','" .. extension_uuid .. "','" .. domain_uuid .."',now(),'" .. from .. "','" .. to .. "','" .. body .. "','" .. direction .. "','','" .. carrier .."')";
		if (debug["sql"]) then
			freeswitch.consoleLog("notice", "[sms] "..sql.."\n");
		end
		dbh:query(sql);
	end