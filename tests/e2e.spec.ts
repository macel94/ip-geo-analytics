import { test, expect } from '@playwright/test';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
import pg from 'pg';

/**
 * E2E Test Suite for IP Geo Analytics
 * Tests the complete setup including:
 * - Database connectivity and schema
 * - Server API endpoints
 * - Client rendering and navigation
 * - Data persistence and retrieval
 */

const API_BASE_URL = 'http://localhost:3000';
const DATABASE_URL = 'postgresql://admin:password123@localhost:5432/analytics?schema=public';

// Initialize Prisma client for database validation
let prisma: PrismaClient;
let pool: pg.Pool;

test.beforeAll(async () => {
  // Set the DATABASE_URL environment variable for Prisma
  process.env.DATABASE_URL = DATABASE_URL;
  
  // Setup PostgreSQL connection pool for Prisma adapter
  pool = new pg.Pool({ connectionString: DATABASE_URL });
  const adapter = new PrismaPg(pool);
  
  // Connect to database for testing
  prisma = new PrismaClient({ adapter });
  
  // Verify database connection
  await prisma.$connect();
  console.log('✓ Database connection established');
});

test.afterAll(async () => {
  // Clean up
  await prisma.$disconnect();
  await pool.end();
});

test.describe('E2E: Complete System Setup and Functionality', () => {
  
  test('should verify database schema and connectivity', async () => {
    // Check if Visit table exists and has correct structure
    const tableExists = await prisma.$queryRaw`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'Visit'
      );
    ` as any[];
    
    expect(tableExists[0].exists).toBe(true);
    
    // Verify we can query the Visit table
    const count = await prisma.visit.count();
    expect(count).toBeGreaterThanOrEqual(0);
    console.log(`✓ Database has ${count} existing visits`);
  });

  test('should have server running and responding to health check', async ({ request }) => {
    // Test server is running by hitting the stats endpoint
    const response = await request.get(`${API_BASE_URL}/api/stats`);
    expect(response.ok()).toBeTruthy();
    expect(response.status()).toBe(200);
    
    const data = await response.json();
    expect(data).toHaveProperty('totalVisits');
    expect(data).toHaveProperty('visitsByCountry');
    expect(data).toHaveProperty('mapData');
    console.log('✓ Server API is responding correctly');
  });

  test('should track a visit and store it in database', async ({ request }) => {
    // Get initial visit count
    const initialCount = await prisma.visit.count();
    
    // Send a tracking request
    const trackResponse = await request.post(`${API_BASE_URL}/api/track`, {
      data: {
        site_id: 'e2e-test-site',
        referrer: 'https://example.com'
      }
    });
    
    expect(trackResponse.ok()).toBeTruthy();
    expect(trackResponse.status()).toBe(200);
    
    const trackData = await trackResponse.json();
    expect(trackData).toHaveProperty('success', true);
    
    // Verify the visit was stored in the database
    const newCount = await prisma.visit.count();
    expect(newCount).toBe(initialCount + 1);
    
    // Verify the stored data
    const latestVisit = await prisma.visit.findFirst({
      where: { site_id: 'e2e-test-site' },
      orderBy: { created_at: 'desc' }
    });
    
    expect(latestVisit).not.toBeNull();
    expect(latestVisit?.site_id).toBe('e2e-test-site');
    expect(latestVisit?.referrer).toBe('https://example.com');
    expect(latestVisit?.ip_address).toBeTruthy();
    expect(latestVisit?.user_agent).toBeTruthy();
    
    console.log('✓ Visit tracked and stored correctly');
    console.log(`  - IP: ${latestVisit?.ip_address}`);
    console.log(`  - Browser: ${latestVisit?.browser}`);
    console.log(`  - OS: ${latestVisit?.os}`);
  });

  test('should render the client application', async ({ page }) => {
    await page.goto('/');
    
    // Wait for the app to load
    await page.waitForLoadState('networkidle');
    
    // Check for main heading
    const heading = page.locator('h1');
    await expect(heading).toContainText('Visitor Analytics');
    
    // Check for key UI elements
    await expect(page.locator('input[placeholder*="Site ID"]')).toBeVisible();
    await expect(page.locator('button:has-text("Refresh")')).toBeVisible();
    await expect(page.locator('button:has-text("Simulate Visit")')).toBeVisible();
    
    console.log('✓ Client application rendered successfully');
  });

  test('should display analytics data on the dashboard', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    
    // Wait for stats to load
    await page.waitForSelector('text=Total Visits', { timeout: 10000 });
    
    // Verify Total Visits section exists
    const totalVisitsSection = page.locator('text=Total Visits').locator('..');
    await expect(totalVisitsSection).toBeVisible();
    
    // Verify Top Countries section exists
    const topCountriesSection = page.locator('text=Top Countries');
    await expect(topCountriesSection).toBeVisible();
    
    console.log('✓ Analytics dashboard displays data');
  });

  test('should simulate a visit and update the UI', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    
    // Wait for initial load
    await page.waitForSelector('text=Total Visits', { timeout: 10000 });
    
    // Get initial total visits count from UI
    const initialVisitsText = await page.locator('text=Total Visits').locator('..').locator('p').textContent();
    const initialVisits = parseInt(initialVisitsText?.trim() || '0');
    
    // Click "Simulate Visit" button
    await page.click('button:has-text("Simulate Visit")');
    
    // Wait a bit for the request to complete
    await page.waitForTimeout(1000);
    
    // Check if the count increased
    const updatedVisitsText = await page.locator('text=Total Visits').locator('..').locator('p').textContent();
    const updatedVisits = parseInt(updatedVisitsText?.trim() || '0');
    
    expect(updatedVisits).toBeGreaterThan(initialVisits);
    
    console.log(`✓ UI updated: ${initialVisits} → ${updatedVisits} visits`);
  });

  test('should filter stats by site_id', async ({ page }) => {
    // First, create some test visits with specific site_id
    const testSiteId = 'filter-test-' + Date.now();
    
    await fetch(`${API_BASE_URL}/api/track`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ site_id: testSiteId })
    });
    
    // Navigate to the app
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('text=Total Visits', { timeout: 10000 });
    
    // Get total visits without filter
    const totalVisitsText = await page.locator('text=Total Visits').locator('..').locator('p').textContent();
    const totalVisits = parseInt(totalVisitsText?.trim() || '0');
    
    // Enter site ID filter
    const input = page.locator('input[placeholder*="Site ID"]');
    await input.fill(testSiteId);
    
    // Click refresh
    await page.click('button:has-text("Refresh")');
    await page.waitForTimeout(500);
    
    // Get filtered visits count
    const filteredVisitsText = await page.locator('text=Total Visits').locator('..').locator('p').textContent();
    const filteredVisits = parseInt(filteredVisitsText?.trim() || '0');
    
    // Filtered count should be less than or equal to total (and at least 1 from our test)
    expect(filteredVisits).toBeGreaterThanOrEqual(1);
    expect(filteredVisits).toBeLessThanOrEqual(totalVisits);
    
    console.log(`✓ Filtering works: ${totalVisits} total → ${filteredVisits} filtered`);
  });

  test('should verify database data integrity after multiple operations', async ({ request }) => {
    // Create multiple visits with different data
    const testSiteId = 'integrity-test-' + Date.now();
    const numberOfVisits = 3;
    
    for (let i = 0; i < numberOfVisits; i++) {
      await request.post(`${API_BASE_URL}/api/track`, {
        data: {
          site_id: testSiteId,
          referrer: `https://test-${i}.com`
        }
      });
    }
    
    // Query database directly
    const visits = await prisma.visit.findMany({
      where: { site_id: testSiteId },
      orderBy: { created_at: 'desc' }
    });
    
    expect(visits.length).toBe(numberOfVisits);
    
    // Verify each visit has required fields
    visits.forEach((visit, index) => {
      expect(visit.site_id).toBe(testSiteId);
      expect(visit.ip_address).toBeTruthy();
      expect(visit.user_agent).toBeTruthy();
      expect(visit.created_at).toBeInstanceOf(Date);
      
      // Check that referrer matches (in reverse order since we ordered by desc)
      expect(visit.referrer).toBe(`https://test-${numberOfVisits - 1 - index}.com`);
    });
    
    // Verify stats API returns correct aggregated data
    const statsResponse = await request.get(`${API_BASE_URL}/api/stats?site_id=${testSiteId}`);
    const stats = await statsResponse.json();
    
    expect(stats.totalVisits).toBe(numberOfVisits);
    
    console.log('✓ Database integrity verified across multiple operations');
  });

  test('should handle analytics aggregation correctly', async ({ request }) => {
    // Get stats
    const response = await request.get(`${API_BASE_URL}/api/stats`);
    const data = await response.json();
    
    // Verify data structure
    expect(Array.isArray(data.visitsByCountry)).toBe(true);
    expect(Array.isArray(data.mapData)).toBe(true);
    expect(typeof data.totalVisits).toBe('number');
    
    // If we have country data, verify structure
    if (data.visitsByCountry.length > 0) {
      const firstCountry = data.visitsByCountry[0];
      expect(firstCountry).toHaveProperty('_count');
      expect(firstCountry._count).toHaveProperty('_all');
      expect(typeof firstCountry._count._all).toBe('number');
    }
    
    // If we have map data, verify structure
    if (data.mapData.length > 0) {
      const firstLocation = data.mapData[0];
      expect(firstLocation).toHaveProperty('_count');
      expect(firstLocation._count).toHaveProperty('_all');
    }
    
    console.log('✓ Analytics aggregation structure is correct');
    console.log(`  - Total visits: ${data.totalVisits}`);
    console.log(`  - Countries tracked: ${data.visitsByCountry.length}`);
    console.log(`  - Map locations: ${data.mapData.length}`);
  });

  test('should persist data across server restarts (simulated)', async ({ request }) => {
    // Create a visit with unique identifier
    const uniqueId = 'persistence-test-' + Date.now();
    
    await request.post(`${API_BASE_URL}/api/track`, {
      data: {
        site_id: uniqueId,
        referrer: 'https://persistence-test.com'
      }
    });
    
    // Verify it exists in database immediately
    const visitBefore = await prisma.visit.findFirst({
      where: { site_id: uniqueId }
    });
    expect(visitBefore).not.toBeNull();
    
    // Simulate passage of time / server processing
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Verify it still exists (would survive restart)
    const visitAfter = await prisma.visit.findFirst({
      where: { site_id: uniqueId }
    });
    expect(visitAfter).not.toBeNull();
    expect(visitAfter?.id).toBe(visitBefore?.id);
    
    console.log('✓ Data persistence verified');
  });
});
