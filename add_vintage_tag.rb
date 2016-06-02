require 'json'
require 'httparty'
require 'pry'
require 'shopify_api'
require 'yaml'

@outcomes = {
  errors: [],
  skipped: [],
  saved_tags: [],
  unable_to_save_tags: [],
  unable_to_add_vintage_tag: [],
  skipped_because_product_has_vintage_tag: [],
  skipped_because_product_has_no_item_condition_metafield: [],
  responses: []
}

#Load secrets from yaml file and set values to use
data = YAML::load(File.open('config/secrets.yml'))
SECURE_URL_BASE = data['url_base']
API_DOMAIN = data['api_domain']

#Constants
DIVIDER = '------------------------------------------'
DELAY_BETWEEN_REQUESTS = 0.11
NET_INTERFACE = HTTParty
STARTPAGE = 1
ENDPAGE = 65

#Need to update to include page range as arguments for do_page_range
# startpage = ARGV[0].to_i
# endpage = ARGV[1].to_i
def main
  puts "starting at #{Time.now}"

  if ARGV[0] =~ /product_id=/
    do_product_by_id(ARGV[0].scan(/product_id=(\d+)/).first.first)
  else
    do_page_range
  end

  puts "finished at #{Time.now}"

  File.open(filename, 'w') do |file|
    file.write @outcomes.to_json
  end

  @outcomes.each_pair do |k,v|
    puts "#{k}: #{v.size}"
  end
end

def filename
  "data/add_vintage_tag_#{Time.now.strftime("%Y-%m-%d_%k%M%S")}.json"
end

def do_page_range
  (STARTPAGE .. ENDPAGE).to_a.each do |current_page|
    do_page(current_page)
  end
end

def do_page(page_number)
  puts "Starting page #{page_number}"

  products = get_products(page_number)

  # counter = 0
  products.each do |product|
    @product_id = product['id']
    do_product(product)
  end

  puts "Finished page #{page_number}"
end

def get_products(page_number)
  response = secure_get("/products.json?page=#{page_number}")

  JSON.parse(response.body)['products']
end

def get_product(id)
  JSON.parse( secure_get("/products/#{id}.json").body )['product']
end

def do_product_by_id(id)
  do_product(get_product(id))
end

def do_product(product)
  begin
    puts DIVIDER
    old_tags = product['tags'].split(', ')
    metafields = metafields_for_product(product)

    if( should_skip_based_on?(metafields, old_tags) )
      skip(product)
    else
      add_vintage_tag(product, old_tags)
    end
  rescue Exception => e
    @outcomes[:errors].push @product_id
    puts "error on product #{product['id']}: #{e.message}"
    puts e.backtrace.join("\n")
    raise e
  end
end

def metafields_for_product(product)
  secure_get("/products/#{product['id']}/metafields.json")
end

def should_skip_based_on?(metafields, old_tags)
    if old_tags.include?('vintage') or old_tags.include?('Vintage')
      @outcomes[:skipped_because_product_has_vintage_tag].push @product_id
      puts "skipping because product has vintage tag"
      return true
    else
      if item_condition = get_metafield(metafields, 'item-condition')
        if item_condition == 'New' or item_conditon == 'new'
          @outcomes[:skipped_because_product_not_vintage].push @product_id
          puts "skipping because product is not vintage"
          return true
        end
      else
        @outcomes[:skipped_because_product_has_no_item_condition_metafield].push @product_id
        puts "skipping because product has no item condition"
        return true
      end
    end
  false
end

def get_metafield(metafields, field_name)
  metafields['metafields'].each do |field|
    if field['key'] == field_name
      return field['value'].strip
    end
  end
  return false
end

def skip(product)
  @outcomes[:skipped].push @product_id
  #puts "Skipping product #{product['id']}"
end

def add_vintage_tag(product, old_tags)
  if new_tags = add_tag(old_tags)
    if result = save_tags(product, new_tags)
      @outcomes[:saved_tags].push @product_id
      puts "Saved tags for #{product['id']}: #{new_tags}"
    else
      @outcomes[:unable_to_save_tags].push @product_id
      puts "Unable to save tags for #{product['id']}:  #{result.body}"
    end
  else
    @outcomes[:unable_to_add_vintage_tag].push @product_id
    puts "unable to add vintage tag for product #{product['id']}"
  end
end

def add_tag(old_tags)
  old_tags.push('vintage')
end

def save_tags(product, new_tags)
  secure_put(
    "/products/#{product['id']}.json",
    {product: {id: product['id'], tags: new_tags}}
  )
end

def secure_get(relative_url)
  sleep DELAY_BETWEEN_REQUESTS
  url = SECURE_URL_BASE + relative_url
  result = NET_INTERFACE.get(url)
end

def secure_put(relative_url, params)
  sleep DELAY_BETWEEN_REQUESTS

  url = SECURE_URL_BASE + relative_url

  result = NET_INTERFACE.put(url, body: params)

  @outcomes[:responses].push({
    method: 'put', requested_url: url, body: result.body, code: result.code
  })
end

def put(url, params)
  NET_INTERFACE.put(url, query: params)
end

main
