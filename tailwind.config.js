module.exports = {
    content: [
        'layouts/**/*.html',
        'content/**/*.md',
    ],
    theme: {
        extend: {
            colors: {
                'ac-background': '#1d1e20'
            },
            fontFamily: {
                'atkinson': [
                    'Atkinson Hyperlegible',
                    '-apple-system',
                    'BlinkMacSystemFont',
                    'segoe ui',
                    'Roboto',
                    'Oxygen',
                    'Ubuntu',
                    'Cantarell',
                    'open sans',
                    'helvetica neue',
                    'sans-serif',
                ]
            }
        },
    },
    plugins: [],
}
