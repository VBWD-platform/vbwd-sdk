# TODO - February 16, 2026

## P0 - Blockers (Must Fix Today)

- [ ] **Fix card SVG display in modal**
  - Card image not showing in CardDetailModal
  - Need to include `image_url` from Arcana in response
  - Test with actual SVG rendering
  - Estimated: 30 mins

- [ ] **Show card name in modal**
  - Modal shows position but not card name
  - Need `arcana.name` field
  - Display prominently (replace or alongside position)
  - Estimated: 15 mins

- [ ] **Load and display card interpretation**
  - Backend returning `null` for interpretation
  - Need to trigger LLM service
  - Display in modal when ready
  - Add loading state while generating
  - Estimated: 45 mins

## P1 - High Priority

- [ ] **Modify Taro routes to include Arcana details**
  - Update `/api/v1/taro/session` response
  - Include full Arcana object in each card
  - Test response payload size

- [ ] **Implement interpretation loading in CardDetailModal**
  - Show loading spinner while generating
  - Handle errors gracefully
  - Cache interpretation in store

- [ ] **Test complete card reading flow**
  - Create session
  - View all 3 cards
  - Check each card detail
  - Verify interpretations

## P2 - Medium Priority

- [ ] **Pre-fetch all Arcana at plugin load**
  - Optimize card lookups
  - Store in Pinia cache
  - Use for modal display

- [ ] **Add Arcana data API endpoint**
  - GET `/api/v1/arcana` - list all
  - GET `/api/v1/arcana/{id}` - single card
  - Include caching headers

- [ ] **Enhance card display**
  - Add card meanings alongside interpretation
  - Show upright/reversed indicator
  - Better visual hierarchy

## P3 - Nice to Have

- [ ] **Follow-up flow testing**
  - Test SAME_CARDS interpretation
  - Test ADDITIONAL card draw
  - Test NEW_SPREAD option

- [ ] **Session history pagination**
  - Load more functionality
  - Date filtering
  - Status filtering

- [ ] **Error handling improvements**
  - Better error messages
  - Retry mechanisms
  - Fallback interpretations

## Completed Today
- ✅ Created devlog structure
- ✅ Fixed locale translations
- ✅ Fixed follow-ups maxed out issue
- ✅ Fixed CardDetailModal props error
- ✅ Created comprehensive system report
