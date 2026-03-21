import { useEffect, useRef, useState } from 'react';
import VisitorMap from './components/Map';

interface Stats {
    totalVisits: number;
    visitsByCountry: Array<{ country: string, _count: { _all: number } }>;
    mapData: Array<{
        city: string | null;
        countryCode: string | null;
        latitude: number | null;
        longitude: number | null;
        _count: { _all: number };
    }>;
}

interface BrowserLocation {
    latitude: number;
    longitude: number;
    city?: string | null;
    country?: string | null;
    countryCode?: string | null;
}

function App() {
    const [stats, setStats] = useState<Stats | null>(null);
    const [siteId, setSiteId] = useState('');
    const [currentLocation, setCurrentLocation] = useState<BrowserLocation | null>(null);
    const locationRequestRef = useRef<Promise<BrowserLocation | null> | null>(null);

    const reverseGeocodeLocation = async (location: BrowserLocation) => {
        const params = new URLSearchParams({
            format: 'jsonv2',
            lat: String(location.latitude),
            lon: String(location.longitude),
            zoom: '10',
            addressdetails: '1',
            layer: 'address',
        });

        const response = await fetch(`https://nominatim.openstreetmap.org/reverse?${params.toString()}`, {
            headers: {
                Accept: 'application/json',
            },
        });

        if (!response.ok) {
            throw new Error('Failed to reverse geocode browser location');
        }

        const data = await response.json();
        const address = data?.address ?? {};
        const city =
            address.city ??
            address.town ??
            address.village ??
            address.municipality ??
            address.suburb ??
            address.county ??
            null;
        const country = address.country ?? null;
        const countryCode = typeof address.country_code === 'string'
            ? address.country_code.toUpperCase()
            : null;

        return {
            city,
            country,
            countryCode,
        };
    };

    const resolveBrowserLocation = async () => {
        if (locationRequestRef.current) {
            return locationRequestRef.current;
        }

        const request = (async () => {
            let nextLocation = currentLocation;

            if (!nextLocation) {
                if (typeof window === 'undefined' || !('geolocation' in navigator)) {
                    return null;
                }

                try {
                    const position = await new Promise<GeolocationPosition>((resolve, reject) => {
                        navigator.geolocation.getCurrentPosition(resolve, reject, {
                            enableHighAccuracy: true,
                            timeout: 10000,
                            maximumAge: 300000,
                        });
                    });

                    nextLocation = {
                        latitude: position.coords.latitude,
                        longitude: position.coords.longitude,
                    };

                    setCurrentLocation(nextLocation);
                } catch (error) {
                    console.warn('Unable to resolve browser location', error);
                    return null;
                }
            }

            if (nextLocation.city || nextLocation.country || nextLocation.countryCode) {
                return nextLocation;
            }

            try {
                const resolvedLocation = {
                    ...nextLocation,
                    ...(await reverseGeocodeLocation(nextLocation)),
                };
                setCurrentLocation(resolvedLocation);
                return resolvedLocation;
            } catch (error) {
                console.warn(
                    'Unable to reverse geocode browser location:',
                    error instanceof Error ? error.message : error,
                );
                return nextLocation;
            }
        })();

        locationRequestRef.current = request;

        try {
            return await request;
        } finally {
            locationRequestRef.current = null;
        }
    };

    const fetchStats = async () => {
        try {
            const query = siteId ? `?site_id=${siteId}` : '';
            const res = await fetch(`/api/stats${query}`);
            const data = await res.json();
            setStats(data);
        } catch (error) {
            console.error('Failed to fetch analytics stats', error);
        }
    };

    useEffect(() => {
        void fetchStats();
        void resolveBrowserLocation();
    }, []);

    // Simple tracking test
    const triggerTestVisit = async () => {
        const browserLocation = await resolveBrowserLocation();
        const response = await fetch('/api/track', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                site_id: siteId || 'demo-site',
                latitude: browserLocation?.latitude,
                longitude: browserLocation?.longitude,
                city: browserLocation?.city,
                country: browserLocation?.country,
                countryCode: browserLocation?.countryCode,
            })
        });

        if (!response.ok) {
            throw new Error('Failed to track visit');
        }

        await fetchStats();
    };

    return (
        <div style={{ padding: '20px', fontFamily: 'sans-serif' }}>
            <h1>Visitor Analytics</h1>
            
            <div style={{ marginBottom: '20px', display: 'flex', gap: '10px' }}>
                <input 
                    type="text" 
                    placeholder="Filter by Site ID" 
                    value={siteId}
                    onChange={(e) => setSiteId(e.target.value)}
                    style={{ padding: '8px' }}
                />
                <button onClick={fetchStats} style={{ padding: '8px 16px' }}>Refresh</button>
                <button onClick={triggerTestVisit} style={{ padding: '8px 16px', background: '#e0e0e0' }}>
                    Simulate Visit
                </button>
            </div>

            {stats ? (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
                    
                    {/* Key Metrics */}
                    <div style={{ background: '#f5f5f5', padding: '20px', borderRadius: '8px' }}>
                        <h2>Total Visits</h2>
                        <p style={{ fontSize: '3em', margin: 0 }}>{stats.totalVisits}</p>
                    </div>

                    <div style={{ background: '#f5f5f5', padding: '20px', borderRadius: '8px' }}>
                        <h2>Top Countries</h2>
                        <ul>
                            {stats.visitsByCountry.map((c: any, i: number) => (
                                <li key={i}>{c.country || 'Unknown'}: {c._count._all}</li>
                            ))}
                        </ul>
                    </div>

                    {/* Map Visualization */}
                    <div style={{ gridColumn: '1 / -1', border: '1px solid #ddd', height: '400px' }}>
                         <VisitorMap data={stats.mapData} currentLocation={currentLocation} />
                     </div>

                </div>
            ) : (
                <p>Loading...</p>
            )}
        </div>
    )
}

export default App
