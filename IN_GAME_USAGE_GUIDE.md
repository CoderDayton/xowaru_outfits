# 🎭 Avatar Stands - In-Game Usage Guide

## 🚀 Getting Started

### 1. **Setup & Launch**
```bash
# In your project directory:
rojo serve

# Then in Roblox Studio:
# - File → Open → Load your place file
# - Connect to local server via Rojo plugin
# - Hit Play to test
```

### 2. **First Time Setup**
- The system auto-initializes when you join the game
- All players get a **Creation UI** button in the top-right corner
- Server handles all data persistence automatically

---

## 🎮 Player Experience

### **Creating Your Avatar Stand**

1. **Open Creation Menu**
   - Click the **"Create Stand"** button (appears in top-right UI)
   - Or walk to an empty area and look for interaction prompts

2. **Placement System**
   - Move around to find a good spot (green placement indicator appears)
   - Click to confirm placement
   - Stand spawns with your current avatar appearance

3. **Customization Options**
   - **Lighting Presets**: Bright, Dramatic, Soft, Natural, Studio
   - **Interaction Range**: 5-50 studs (how close players need to be)
   - **Rotation Speed**: 0-5 (how fast the avatar rotates)
   - **Camera Settings**: Distance and height for viewing

### **Interacting with Stands**

1. **View Mode**
   - Walk within 12 studs of any avatar stand
   - UI automatically appears showing avatar details
   - Use mouse/camera to orbit around the stand

2. **Avatar Customization** (for your own stands)
   - Click **"Edit Avatar"** on your stands
   - Opens Roblox's Avatar Editor integration
   - Changes save automatically to your stand

### **Managing Your Stands**
- **View All Stands**: Check creation UI for your stand list
- **Delete Stands**: Use the manage menu in the UI
- **Update Settings**: Modify lighting, range, rotation anytime

---

## 🎯 Key Features

### **Smart Proximity System**
- Stands only load when players are nearby (100 stud range)
- Automatic cleanup when players leave areas
- Performance optimized for 20+ concurrent stands

### **Avatar Integration**
- Full Roblox Catalog support via AvatarEditorService
- Automatic outfit syncing across all clients
- Preserves all accessories, body colors, scaling

### **Lighting Presets**
- **Bright**: High exposure, minimal shadows - great for showing details
- **Dramatic**: Dark ambient, strong contrasts - cinematic feel  
- **Soft**: Gentle lighting - natural and flattering
- **Natural**: Balanced lighting - everyday appearance
- **Studio**: Professional lighting - clean and bright

### **Persistence System**
- All stands save automatically to DataStore
- Survives server restarts and player leaves/joins
- Individual player data isolation

---

## 🛠️ Admin/Developer Features

### **Configuration** (in `Config.luau`)
```luau
-- Adjust these values for your game:
maxVisibleStands = 20,        -- Max stands loaded per player
cullingDistance = 100,        -- When stands unload
interactionRange = 12,        -- Default interaction distance
updateInterval = 0.1,         -- Network update frequency
```

### **Server Controls**
- All stand data accessible via `AvatarStandManager`
- Can force-delete stands, bulk operations
- Analytics available through data layer

### **Performance Monitoring**
- Check server console for memory usage
- Client shows loading states automatically  
- Network events logged with stand IDs

---

## 🎨 Customization Examples

### **Theme Park Setup**
```luau
-- Great for showcase areas
interactionRange = 8,
lightingPreset = "Studio",
rotationSpeed = 0.5,
```

### **Social Hub**
```luau
-- Players showing off outfits
interactionRange = 15,
lightingPreset = "Natural", 
rotationSpeed = 1.2,
```

### **Fashion Show**
```luau
-- Dramatic presentation
interactionRange = 20,
lightingPreset = "Dramatic",
rotationSpeed = 0.3,
```

---

## 🐛 Troubleshooting

### **Stand Won't Create**
- Check if you have permissions (server validates ownership)
- Try moving to a different location
- Ensure you're not at the max stand limit per player

### **Avatar Not Updating**
- Stand avatar updates are server-authoritative
- Changes may take 1-2 seconds to sync to all clients
- Try refreshing by walking away and back

### **Performance Issues**
- Reduce `maxVisibleStands` in config
- Increase `cullingDistance` to load fewer stands
- Check for too many stands in one area

### **UI Not Appearing**
- Ensure you're within interaction range of a stand
- Check console for any script errors
- UI auto-hides after 30 seconds of no interaction

---

## 🔧 Integration Tips

### **Adding to Existing Games**
1. Copy the `src/` folder structure to your project
2. Ensure DataStore API is enabled in game settings
3. Add creation buttons to your existing UI systems
4. Configure interaction ranges for your game's scale

### **Custom UI Integration**
- Hook into the State system for reactive UI updates
- Use RemoteSignal events to trigger custom animations
- Access stand data through the client manager

### **Monetization Ideas**
- Premium lighting presets
- Exclusive avatar items for stands
- Stand decoration/background systems
- Social features (likes, comments, sharing)

---

## 📊 System Events

The system broadcasts these events you can listen to:

```luau
-- Player events
"INTERACTION_ZONE_ENTERED" -- Player approached a stand
"INTERACTION_ZONE_EXITED"  -- Player left a stand
"UI_STATE_CHANGED"         -- UI view changed (useful for custom UI)

-- Stand events  
"STAND_CREATED"           -- New stand spawned
"STAND_REMOVED"           -- Stand deleted
"AVATAR_UPDATED"          -- Stand avatar changed
```

---

## 🎪 Ready to Use!

Your Avatar Stands system is **production-ready** with:
- ✅ Complete server-client architecture
- ✅ Data persistence & memory management  
- ✅ Roblox Avatar Editor integration
- ✅ Performance optimization
- ✅ Error handling & validation
- ✅ Configurable lighting & interaction

**Load it up in Studio and start creating stands!** 🚀