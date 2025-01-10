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
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap">
        <style>
          :root {
            --bg-primary: #1a1b1e;
            --bg-secondary: #25262b;
            --text-primary: #ffffff;
            --text-secondary: #a1a1aa;
            --accent: #0ea5e9;
            --accent-hover: #0284c7;
            --error: #ef4444;
            --success: #22c55e;
          }

          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }

          body {
            font-family: 'Inter', sans-serif;
            background-color: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 2rem;
          }

          .container {
            width: 100%;
            max-width: 800px;
            margin: 2rem auto;
          }

          .card {
            background-color: var(--bg-secondary);
            padding: 2rem;
            border-radius: 1rem;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
            margin-top: 2rem;
          }

          h1 {
            font-size: 2.5rem;
            font-weight: 600;
            text-align: center;
            margin-bottom: 0.5rem;
            background: linear-gradient(to right, var(--accent), #818cf8);
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
          }

          h2 {
            font-size: 1.5rem;
            font-weight: 500;
            color: var(--text-primary);
            margin-bottom: 1.5rem;
          }

          input[type="text"] {
            width: 100%;
            padding: 1rem;
            margin: 0.5rem 0;
            border: 2px solid var(--bg-primary);
            border-radius: 0.5rem;
            background-color: var(--bg-primary);
            color: var(--text-primary);
            font-size: 1rem;
            transition: all 0.3s ease;
          }

          input[type="text"]:focus {
            outline: none;
            border-color: var(--accent);
            box-shadow: 0 0 0 2px rgba(14, 165, 233, 0.2);
          }

          button {
            width: 100%;
            padding: 1rem;
            margin-top: 1rem;
            border: none;
            border-radius: 0.5rem;
            background-color: var(--accent);
            color: white;
            font-size: 1rem;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s ease;
          }

          button:hover {
            background-color: var(--accent-hover);
            transform: translateY(-1px);
          }

          button:active {
            transform: translateY(0);
          }

          .optional {
            color: var(--text-secondary);
            font-size: 0.875rem;
            margin-top: 0.5rem;
          }

          #result {
            margin-top: 1.5rem;
            padding: 1rem;
            border-radius: 0.5rem;
            background-color: var(--bg-primary);
            display: none;
          }

          #result.success {
            border-left: 4px solid var(--success);
          }

          #result.error {
            border-left: 4px solid var(--error);
          }

          .result-item {
            margin: 0.5rem 0;
          }

          .result-label {
            color: var(--text-secondary);
            font-size: 0.875rem;
            margin-bottom: 0.25rem;
          }

          .result-value {
            color: var(--text-primary);
            word-break: break-all;
          }

          .result-value a {
            color: var(--accent);
            text-decoration: none;
          }

          .result-value a:hover {
            text-decoration: underline;
          }

          @media (max-width: 640px) {
            body {
              padding: 1rem;
            }

            .card {
              padding: 1.5rem;
            }

            h1 {
              font-size: 2rem;
            }
          }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>URL Shortener</h1>
          <div class="card">
            <h2>Shorten your URL</h2>
            <input type="text" id="urlInput" placeholder="Enter your URL here (e.g., https://example.com)" 
                   spellcheck="false" autocomplete="off">
            <input type="text" id="customCode" placeholder="Custom short code (optional)" 
                   spellcheck="false" autocomplete="off">
            <p class="optional">Custom code must be 4-10 characters long, using only letters, numbers, underscores, and hyphens</p>
            <button onclick="shortenUrl()">Shorten URL</button>
            <div id="result"></div>
          </div>
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
                resultDiv.className = 'success';
                resultDiv.style.display = 'block';
                resultDiv.innerHTML = `
                  <div class="result-item">
                    <div class="result-label">Original URL</div>
                    <div class="result-value">${data.original_url}</div>
                  </div>
                  <div class="result-item">
                    <div class="result-label">Shortened URL</div>
                    <div class="result-value">
                      <a href="${data.shortened_url}" target="_blank">${data.shortened_url}</a>
                    </div>
                  </div>
                `;
              } else {
                resultDiv.className = 'error';
                resultDiv.style.display = 'block';
                resultDiv.innerHTML = `
                  <div class="result-item">
                    <div class="result-value" style="color: var(--error)">Error: ${data.error}</div>
                  </div>
                `;
              }
            } catch (error) {
              resultDiv.className = 'error';
              resultDiv.style.display = 'block';
              resultDiv.innerHTML = `
                <div class="result-item">
                  <div class="result-value" style="color: var(--error)">Error: Something went wrong</div>
                </div>
              `;
            }
          }

          // Add keyboard shortcut for submitting
          document.addEventListener('keydown', function(event) {
            if (event.key === 'Enter') {
              shortenUrl();
            }
          });
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