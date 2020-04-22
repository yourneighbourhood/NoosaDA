require 'scraperwiki'
require 'mechanize'
require 'uri'

class Mechanize::Form
  def postback target, argument
    self['__EVENTTARGET'], self['__EVENTARGUMENT'] = target, argument
    submit
  end
end

class Hash
  def has_blank?
    self.values.any?{|v| v.nil? || v.length == 0}
  end
end

case ENV['MORPH_PERIOD']
  when 'lastmonth'
  	period = "LM"
  when 'thismonth'
  	period = "TM"
  else
    period = "TW"
  	ENV['MORPH_PERIOD'] = 'thisweek'
end
puts "Getting data in `" + ENV['MORPH_PERIOD'] + "`, changable via MORPH_PERIOD environment"

url         = 'https://noo-web.t1cloud.com/T1PRDefault/WebApps/eProperty/P1/eTrack/eTrackApplicationSearchResults.aspx?Field=S&Period=' + period +'&r=P1.WEBGUEST&f=$P1.ETR.SEARCH.S' + period
info_url    = 'https://noo-web.t1cloud.com/T1PRDefault/WebApps/eProperty/P1/eTrack/eTrackApplicationDetails.aspx?r=P1.WEBGUEST&f=$P1.ETR.APPDET.VIW&ApplicationId='
comment_url = 'mailto:mail@noosa.qld.gov.au'

agent = Mechanize.new
agent_detail_page = Mechanize.new
page = agent.get(url)

if page.search("tr.pagerRow").empty?
  totalPages = 1
else
  target, argument = page.search("tr.pagerRow").search("td")[-1].at('a')['href'].scan(/'([^']*)'/).flatten
  while page.search("tr.pagerRow").search("td")[-1].inner_text == '...' do
    target, argument = page.search("tr.pagerRow").search("td")[-1].at('a')['href'].scan(/'([^']*)'/).flatten
    page = page.form.postback target, argument
  end
  totalPages = page.search("tr.pagerRow").search("td")[-1].inner_text.to_i
end

(1..totalPages).each do |i|
  puts "Scraping page " + i.to_s + " of " + totalPages.to_s

  if i == 1
    page = agent.get(url)
  else
    page = page.form.postback target, 'Page$' + i.to_s
  end

  results = page.search("tr.normalRow, tr.alternateRow")
  results.each do |result|
    detail_page = agent_detail_page.get( info_url + URI::encode_www_form_component(result.search("td")[0].inner_text) )
    address = detail_page.search('td.headerColumn[contains("Address")] ~ td').inner_text

    record = {
      'council_reference' => result.search("td")[0].inner_text.to_s,
      'address'           => address,
      'description'       => result.search("td")[2].inner_text.to_s.squeeze,
      'info_url'          => info_url + URI::encode_www_form_component(result.search("td")[0].inner_text),
      'comment_url'       => comment_url,
      'date_scraped'      => Date.today.to_s,
      'date_received'     => Date.parse(result.search("td")[1]).to_s
    }

    if record.has_blank?
      puts 'Something is blank, skipping record ' + record['council_reference']
      puts record
    else
      if (ScraperWiki.select("* from data where `council_reference`='#{record['council_reference']}'").empty? rescue true)
        puts "Saving record " + record['council_reference'] + " - " + record['address']
#       puts record
        ScraperWiki.save_sqlite(['council_reference'], record)
      else
        puts 'Skipping already saved record ' + record['council_reference']
      end
    end
  end
end
