require 'sinatra'
require 'sinatra/json'
require 'sqlite3'
require 'securerandom'
require 'base62-rb'
require 'uri'

# Enable serving static files from public directory
set :public_folder, File.dirname(__FILE__) + '/public'

# Database setup
def init_db
  db = SQLite3::Database.new 'urls.db'
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS urls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      original_url TEXT NOT NULL,
      short_code TEXT NOT NULL UNIQUE,
      custom BOOLEAN DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL
  db.close
end

init_db

# Helper to validate URL
def valid_url?(url)
  uri = URI.parse(url)
  uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
rescue URI::InvalidURIError
  false
end

# Helper to validate custom short code
def valid_short_code?(code)
  return false if code.nil? || code.empty?
  return false if code.length < 4 || code.length > 10
  code.match?(/^[a-zA-Z0-9_-]+$/)
end

# Helper to check if short code is available
def short_code_available?(db, code)
  result = db.get_first_row('SELECT 1 FROM urls WHERE short_code = ?', [code])
  result.nil?
end

# Helper to generate a unique short code
def generate_short_code(db)
  loop do
    short_code = rand(36**6).to_s(36)
    return short_code if short_code_available?(db, short_code)
  end
end

# Root route - Welcome page
get '/' do
  <<-HTML
    <!DOCTYPE html>
    <html>
      <head>
        <title>URL Shortener</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            line-height: 1.6;
          }
          .container {
            background: #f5f5f5;
            padding: 20px;
            border-radius: 5px;
            margin-top: 20px;
          }
          input[type="text"] {
            width: 100%;
            padding: 8px;
            margin: 10px 0;
            border: 1px solid #ddd;
            border-radius: 4px;
          }
          button {
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 4px;
            cursor: pointer;
          }
          button:hover {
            background: #0056b3;
          }
          #result {
            margin-top: 20px;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            display: none;
          }
          .optional {
            color: #666;
            font-size: 0.9em;
          }
        </style>
      </head>
      <body>
        <h1>URL Shortener</h1>
        <div class="container">
          <h2>Shorten your URL</h2>
          <input type="text" id="urlInput" placeholder="Enter your URL here (e.g., https://example.com)">
          <input type="text" id="customCode" placeholder="Custom short code (optional)" class="optional">
          <p class="optional">Custom code must be 4-10 characters long, using only letters, numbers, underscores, and hyphens</p>
          <button onclick="shortenUrl()">Shorten URL</button>
          <div id="result"></div>
        </div>

        <script>
          async function shortenUrl() {
            const urlInput = document.getElementById('urlInput');
            const customCode = document.getElementById('customCode');
            const resultDiv = document.getElementById('result');
            
            try {
              const response = await fetch('/shorten', {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({ 
                  url: urlInput.value,
                  custom_code: customCode.value || undefined
                })
              });
              
              const data = await response.json();
              
              if (response.ok) {
                resultDiv.style.display = 'block';
                resultDiv.innerHTML = `
                  <p>Original URL: ${data.original_url}</p>
                  <p>Shortened URL: <a href="${data.shortened_url}" target="_blank">${data.shortened_url}</a></p>
                `;
              } else {
                resultDiv.style.display = 'block';
                resultDiv.innerHTML = `<p style="color: red;">Error: ${data.error}</p>`;
              }
            } catch (error) {
              resultDiv.style.display = 'block';
              resultDiv.innerHTML = '<p style="color: red;">Error: Something went wrong</p>';
            }
          }
        </script>
      </body>
    </html>
  HTML
end

# Create a new shortened URL
post '/shorten' do
  content_type :json
  request_payload = JSON.parse(request.body.read)
  original_url = request_payload['url']
  custom_code = request_payload['custom_code']

  return json(error: 'URL is required') unless original_url
  return json(error: 'Invalid URL format') unless valid_url?(original_url)
  
  if custom_code
    return json(error: 'Invalid custom code format') unless valid_short_code?(custom_code)
  end

  db = SQLite3::Database.new 'urls.db'
  db.results_as_hash = true

  begin
    if custom_code
      return json(error: 'Custom code already taken') unless short_code_available?(db, custom_code)
      short_code = custom_code
    else
      short_code = generate_short_code(db)
    end

    db.execute(
      'INSERT INTO urls (original_url, short_code, custom) VALUES (?, ?, ?)',
      [original_url, short_code, custom_code ? 1 : 0]
    )
    
    shortened_url = "#{request.base_url}/#{short_code}"
    json(shortened_url: shortened_url, original_url: original_url)
  rescue SQLite3::ConstraintException
    # If we get a duplicate short code, try again (should only happen for generated codes)
    retry unless custom_code
  ensure
    db.close
  end
end

# Redirect to original URL
get '/:short_code' do
  short_code = params[:short_code]
  return if short_code == 'favicon.ico'
  
  db = SQLite3::Database.new 'urls.db'
  db.results_as_hash = true

  result = db.get_first_row('SELECT original_url FROM urls WHERE short_code = ?', [short_code])
  db.close

  if result
    redirect result['original_url']
  else
    status 404
    json(error: 'URL not found')
  end
end

# Get URL info
get '/info/:short_code' do
  content_type :json
  short_code = params[:short_code]
  
  db = SQLite3::Database.new 'urls.db'
  db.results_as_hash = true

  result = db.get_first_row('SELECT * FROM urls WHERE short_code = ?', [short_code])
  db.close

  if result
    json(
      short_code: result['short_code'],
      original_url: result['original_url'],
      created_at: result['created_at']
    )
  else
    status 404
    json(error: 'URL not found')
  end
end

# Delete a shortened URL
delete '/:short_code' do
  short_code = params[:short_code]
  
  db = SQLite3::Database.new 'urls.db'
  db.execute('DELETE FROM urls WHERE short_code = ?', [short_code])
  db.close
  
  status 200
  body ''
end 