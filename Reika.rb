require 'addressable'
require 'faraday'
require 'discordrb'

require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/filters'
require 'active_support/core_ext/numeric/conversions'
require 'active_support/core_ext/array/wrap'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/date'

require 'date'
require 'json'
require 'uri'


if ENV['DISCORD_TOKEN'].blank? || ENV['STEAM_API_KEY'].blank?
  throw NotImplementedError, "you need to specify 'DISCORD_TOKEN' and 'STEAM_API_KEY'"
end


CitiesAppID = 255710
DynoID = '155149108183695360'

bot = Discordrb::Bot.new(
  token: ENV['DISCORD_TOKEN'],
  ignore_bots: true,
)

WorkshopURL = Addressable::Template.new(
  '{http,https}://steamcommunity.com/{sharedfiles,workshop}/filedetails/{?id,params*}'
)

class SteamAPI
  APIKey = ENV['STEAM_API_KEY']
  Endpoint = Addressable::URI.parse('https://api.steampowered.com')
  EndpointTemplate = Addressable::Template.new(
    "{resource}/{target}/{version}/"
  )
  SteamUser = EndpointTemplate.partial_expand(resource: 'ISteamUser')
  RemoteStorage = EndpointTemplate.partial_expand(resource: 'ISteamRemoteStorage')


  def initialize
    @conn = Faraday.new(url: Endpoint)
  end


  def PlayerSummaries(ids)
    ids = Array.wrap(ids)

    @conn.get SteamUser.expand(target: 'GetPlayerSummaries', version: 'v2'), {
      key: APIKey,
      steamids: ids.join(','),
    }
  end

  def PublishedFileDetails(ids)
    ids = Array.wrap(ids)

    @conn.post RemoteStorage.expand(target: 'GetPublishedFileDetails', version: 'v1'), {
      itemcount: ids.length

    }.merge(Hash[
      ids.map.with_index {|id, i| ["publishedfileids[#{i}]", id] }
    ])
  end
end

def sanitize_d(text)
  text.gsub(/`/, '\\\\`')
end

bot.message do |ev|
  api = SteamAPI.new

  urls = URI.extract(ev.message.text).uniq
  ignored_urls = urls.select {|url|
    ev.message.text.to_s.include? "<#{url.to_s}>"
  }

  # puts urls, ignored_urls

  urls.each do |url_raw|
    next if ignored_urls.include?(url_raw)
    url = Addressable::URI.parse(url_raw)
    params = WorkshopURL.extract(url)

    next unless params
    puts "[message] #{ev.user.name} (#{ev.user.id}): #{ev.message}"

    j = JSON.parse(api.PublishedFileDetails(Integer(params['id'])).body)
    j['response']['publishedfiledetails'].each do |item|
      next unless item['visibility'] == 0
      next if item['banned'] != 0

      ev.channel.send_embed do |embed|
        # item['description'] = ''
        tags = item['tags'].map {|e| e['tag']}
        embed.color = tags.include?('Mod') ? '#ff71ef' : '#ff9153'

        embed.title = "#{item['title']}"

        desc = item['description']
        urls_in_desc = URI.extract(desc).uniq
        urls_in_desc.each do |url|
          desc.gsub!(url, '')
        end

        embed.description = desc
          .gsub(/\n|\r\n/, ' ')
          .gsub(/\[\/?[^\]]+?\]/, ' ')
          .gsub(/`/, '\\`')
          .gsub(/[:@]/, '`\1`')
          .gsub(/\s+/, ' ')
          .truncate(200, separator: /\p{Zs}/, omission: ' ...')

        embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(
          url: Addressable::URI.parse(item['preview_url']).to_s
        )
        embed.url = url

        creator = JSON.parse(api.PlayerSummaries(item['creator']).body)['response']['players'][0]
        # puts creator

        embed.add_field(
          name: ":white_check_mark: **#{item['subscriptions'].to_s(:delimited)}**",
          value: [
            ":hearts: **#{item['favorited'].to_s(:delimited)}**",
            ":eye: **#{item['views'].to_s(:delimited)}**",
          ].join(' '),
          inline: true
        )

        name = "#{sanitize_d(creator['personaname'])}"
        realname = creator['realname'].present? ? "(#{sanitize_d(creator['realname'])})" : ''

        embed.author = Discordrb::Webhooks::EmbedAuthor.new(
          name: [name, realname].join(' '),
          url: creator['profileurl'],
          icon_url: creator['avatar'],
        )

        # embed.add_field(
        #   name: [':spy:'].compact.join(' '),
        #   value: [name, realname, flag].join(' '),
        #   inline: true,
        # )

        # flag = creator['loccountrycode'].present? ? ":flag_#{sanitize_d(creator['loccountrycode']).downcase}:" : nil
        updated = Time.at(item['time_updated']).to_datetime
        updatedDelta = (DateTime.now - updated).to_i
        updatedDeltaL = \
          case updatedDelta
          when 0
            "Today"
          when 1
            "Yesterday"
          else
            "#{updatedDelta} days ago"
          end

        embed.add_field(name: ":file_folder: **\`#{item['file_size'].to_s(:human_size)}\`**", value: ":tools: Last update: #{updatedDeltaL}#{updatedDelta <= 7 ? ' :new:' : ''}", inline: true)

        embed.timestamp = Time.at(item['time_created'])
        embed.footer = Discordrb::Webhooks::EmbedFooter.new(
          text: tags.map {|tag| sanitize_d(tag) }.join(', ')
        )
      end
    end

    # puts j
  end
end

bot.mention do |ev|
  next unless ev.message.mentions.any? {|u| u.current_bot? }

  # Dyno
  if ev.message.text =~ /意気込み/
    puts ev.message.text
    ev.channel.send_message "<@#{DynoID}> あんたには負けないんだから"
  end
end


loop do
  begin
    bot.run
  rescue => e
    puts e
  end
end
