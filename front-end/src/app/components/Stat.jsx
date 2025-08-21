export default function Stat({ label, value, full = false }) {
    return (
        <div className={full ? "col-span-2" : ""}>
            <p className="text-xs uppercase tracking-wide text-gray-500">{label}</p>
            <p className="text-lg font-semibold">{value}</p>
        </div>
    );
}