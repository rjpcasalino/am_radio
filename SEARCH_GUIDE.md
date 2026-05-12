# Radio Station Discovery Guide

This guide explains how to discover and add new radio stations using the enhanced Radio-Browser.info search functionality in `am_radio.pl`.

## Quick Start

### Quick Search (Simple Name/Keyword)
```bash
# Search for stations with 'jazz' in the name
perl am_radio.pl -f 'jazz'

# Search for BBC stations
perl am_radio.pl -f 'BBC'

# Search for classical music
perl am_radio.pl -f 'classical'
```

### Interactive Menu (Advanced Search)
```bash
# Launch the interactive search menu
perl am_radio.pl -f

# Or simply omit the query after -f
perl am_radio.pl -f ''
```

## Search Options

The interactive menu provides 6 different search methods:

### 1. By Station Name or Keyword
Search for stations by name or keyword. This is the same as the quick search mode.

**Examples:**
- `jazz` - Find stations with "jazz" in the name
- `BBC` - Find BBC radio stations
- `rock` - Find rock music stations

### 2. By Country
Search for stations broadcasting from a specific country.

**Examples:**
- `USA` - Stations in the United States
- `Germany` - German stations
- `Brazil` - Brazilian stations
- `Japan` - Japanese stations
- `United Kingdom` - UK stations

### 3. By Country + State/Region
Narrow down your search to a specific state or region within a country.

**Examples:**
- Country: `USA`, State: `California`
- Country: `Australia`, State: `New South Wales`
- Country: `Canada`, State: `Ontario`
- Country: `Germany`, State: `Bavaria`

### 4. By Tag/Genre
Search for stations based on music genre or content tags.

**Popular Tags:**
- `jazz` - Jazz music
- `classical` - Classical music
- `news` - News stations
- `rock` - Rock music
- `electronic` - Electronic/EDM
- `pop` - Pop music
- `talk` - Talk radio
- `sports` - Sports coverage
- `hiphop` - Hip-hop/rap
- `country` - Country music
- `blues` - Blues music
- `reggae` - Reggae music

### 5. By Language
Find stations broadcasting in a specific language.

**Examples:**
- `english` - English language stations
- `spanish` - Spanish language stations
- `french` - French language stations
- `german` - German language stations
- `portuguese` - Portuguese language stations
- `italian` - Italian language stations
- `chinese` - Chinese language stations
- `arabic` - Arabic language stations

### 6. Advanced Multi-Criteria Search
Combine multiple search criteria for precise results. Leave any field blank to skip it.

**Example Search:**
```
Station name/keyword: rock
Country: USA
State/Region: California
Tag/Genre: rock
Language: english
```

This would find English-language rock stations from California, USA.

## Search Results

Results are displayed with enhanced metadata:

```
  1) KEXP Seattle (music + talk)
     Location: Washington, USA
     Quality: 128 kbps | Votes: 1523
     Language: english
     Tags: rock, indie, alternative, eclectic

  2) WFMU Freeform Radio
     Location: New Jersey, USA
     Quality: 128 kbps | Votes: 892
     Language: english
     Tags: freeform, eclectic, indie
```

### Metadata Explained
- **Location**: State/region and country where the station is based
- **Quality**: Bitrate in kbps (higher = better audio quality)
- **Votes**: Community popularity votes (higher = more popular/reliable)
- **Language**: Primary broadcast language
- **Tags**: Genre and content descriptors

## Result Sorting

All search results are sorted by:
1. **Vote count** (descending) - Most popular stations first
2. **Only working stations** - Broken streams are filtered out

This ensures you get the most reliable, high-quality stations at the top of the results.

## Saving Stations

After viewing search results, you'll be prompted:

```
Enter a number to SAVE to your list (or press Enter to exit):
```

- Enter a number (1-25) to save that station to `~/.radio_stations`
- Press Enter to exit without saving

Saved stations can be played with:
```bash
perl am_radio.pl -l    # List saved stations
perl am_radio.pl -s 3  # Play station #3
perl am_radio.pl -t    # Launch TUI mode
```

## Tips for Better Results

1. **Be specific with countries**: Use full names or ISO codes
   - ✓ `USA`, `United States`
   - ✓ `Germany`, `Deutschland`
   - ✓ `United Kingdom`, `UK`

2. **Use common tag names**: Stick to popular genres
   - ✓ `jazz`, `rock`, `classical`, `news`
   - ✗ `jazzy`, `jazz-fusion` (too specific)

3. **Try broader searches first**: Start with country/language, then narrow down
   - First: Search by country
   - Then: Add state/region
   - Finally: Filter by tag/genre

4. **Check the vote count**: Higher votes generally mean:
   - More reliable stream
   - Better quality
   - More consistent uptime

5. **Use multi-criteria search for precision**:
   - Combine country + language + tag for targeted results
   - Example: `USA` + `english` + `classical` for American classical stations

## Examples

### Find Jazz Stations in New York
```bash
perl am_radio.pl -f
# Select: 3 (By country + state)
# Country: USA
# State: New York
```

### Find German News Stations
```bash
perl am_radio.pl -f
# Select: 6 (Advanced search)
# Country: Germany
# Tag/Genre: news
# Language: german
```

### Quick Classical Music Search
```bash
perl am_radio.pl -f 'classical'
```

### Find Spanish-Language Stations
```bash
perl am_radio.pl -f
# Select: 5 (By language)
# Language: spanish
```

## Troubleshooting

### "Could not parse response from Radio-Browser.info"
- **Cause**: Network connectivity issue or API temporarily down
- **Solution**: Check internet connection, try again in a few minutes

### "No active stations found"
- **Cause**: Search criteria too specific or no matches
- **Solution**: Broaden search terms, try different keywords

### "curl" not found
- **Cause**: curl is not installed
- **Solution**: Install curl with your package manager
  ```bash
  # Debian/Ubuntu
  sudo apt install curl

  # macOS
  brew install curl

  # Fedora/RHEL
  sudo dnf install curl
  ```

## API Information

This script uses the free Radio-Browser.info API:
- **Endpoint**: https://de1.api.radio-browser.info
- **Documentation**: https://api.radio-browser.info/
- **Rate Limits**: None for normal use
- **Terms**: Free and open API for radio station discovery

## Contributing

Found a great station? Share it with others by:
1. Adding it to Radio-Browser.info directly
2. Sharing your `~/.radio_stations` file
3. Contributing to this project on GitHub

---

**Pro Tip**: The more specific your search criteria, the fewer results you'll get. Start broad and narrow down!
