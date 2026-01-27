import appscript

def debug_track_id():
    try:
        music = appscript.app('Music')
        if music.player_state() != appscript.k.playing:
            print("Music is not playing. Please play a track to test.")
            return

        current = music.current_track
        db_id = current.database_ID()
        print(f"Current Track: {current.name()} | ID: {db_id} (Type: {type(db_id)})")

        # Try robust approach
        try:
            # Use 'its' for filter
            query = appscript.its.database_ID == db_id
            
            # Search in Library
            matches = music.library_playlists[1].tracks[query].get()
            if matches:
                print(f"Found via Library search (robust): {matches[0].name()}")
            else:
                print("Library search (robust) found 0 matches.")
                
        except Exception as e:
             print(f"Library search (robust) failed: {e}")

    except Exception as e:
        print(f"General Error: {e}")

if __name__ == "__main__":
    debug_track_id()
