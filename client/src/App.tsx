import { useEffect, useState } from 'react';
import VisitorMap from './components/Map';

interface Stats {
    totalVisits: number;
    visitsByCountry: Array<{ country: string, _count: { _all: number } }>;
    mapData: Array<any>;
}

function App() {
    const [stats, setStats] = useState<Stats | null>(null);
    const [siteId, setSiteId] = useState('');

    const fetchStats = async () => {
        const query = siteId ? `?site_id=${siteId}` : '';
        const res = await fetch(`/api/stats${query}`);
        const data = await res.json();
        setStats(data);
    };

    useEffect(() => {
        fetchStats();
    }, []);

    // Simple tracking test
    const triggerTestVisit = async () => {
        await fetch('/api/track', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ site_id: siteId || 'demo-site' })
        });
        fetchStats();
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
                         <VisitorMap data={stats.mapData} />
                    </div>

                </div>
            ) : (
                <p>Loading...</p>
            )}
        </div>
    )
}

export default App
