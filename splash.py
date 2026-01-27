
# Embedded HTML for splash screen
SPLASH_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Initializing...</title>
    <style>
        body, html {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            background-color: #000;
            color: #fff;
            display: flex;
            align-items: center;
            justify-content: center;
            overflow: hidden;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }
        .container {
            text-align: center;
            opacity: 0;
            animation: fadeInContainer 3s forwards;
        }
        .logo {
            width: 128px;
            height: 128px;
            margin: 0 auto;
            opacity: 0;
            transform: scale(0.9);
            animation: fadeInLogo 1s 0.5s forwards;
        }
        .text-content {
            margin-top: 2rem;
            opacity: 0;
            transform: translateY(4px);
            animation: fadeInText 1s 1.5s forwards;
        }
        h1 {
            font-size: 1.875rem;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 0.3em;
            text-shadow: 0 0 8px rgba(255, 255, 255, 0.15);
        }
        p {
            margin-top: 1rem;
            font-size: 0.75rem;
            color: #888;
            font-family: monospace;
            text-transform: uppercase;
            letter-spacing: 0.1em;
        }

        @keyframes fadeInContainer {
            0% { opacity: 0; }
            20% { opacity: 1; }
            80% { opacity: 1; }
            100% { opacity: 0; }
        }
        @keyframes fadeInLogo {
            to { opacity: 1; transform: scale(1); }
        }
        @keyframes fadeInText {
            to { opacity: 1; transform: translateY(0); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">
            <!-- Simplified SVG Logo -->
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="none">
              <path d="M50 0 L100 25 V75 L50 100 L0 75 V25 Z" stroke="#555" stroke-width="2"/>
              <path d="M50 10 L90 30 V70 L50 90 L10 70 V30 Z" stroke="#FFF" stroke-width="3"/>
              <circle cx="50" cy="50" r="15" stroke="#FFF" stroke-width="2"/>
            </svg>
        </div>
        <div class="text-content">
            <h1>Azathoth's Whisper</h1>
            <p>Initializing Core Logic</p>
        </div>
    </div>
</body>
</html>
"""
